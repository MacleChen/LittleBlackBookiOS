import SwiftUI
import WebKit

// MARK: - Settings

class ReaderSettings: ObservableObject {
    @AppStorage("r_fontSize") var fontSize: Double  = 20
    @AppStorage("r_theme")    var themeRaw: String  = ReaderTheme.white.rawValue
    @AppStorage("r_font")     var fontRaw:  String  = ReaderFont.system.rawValue
    var theme: ReaderTheme { get { .init(rawValue: themeRaw) ?? .white } set { themeRaw = newValue.rawValue } }
    var font:  ReaderFont  { get { .init(rawValue: fontRaw)  ?? .system } set { fontRaw  = newValue.rawValue } }
}

enum ReaderTheme: String, CaseIterable {
    case white, sepia, dark, night
    var label: String { switch self { case .white:"白天"; case .sepia:"护眼"; case .dark:"深色"; case .night:"夜间" } }
    var bg: String    { switch self { case .white:"#FFFFFF"; case .sepia:"#F5EDD6"; case .dark:"#1C1C1E"; case .night:"#000000" } }
    var fg: String    { switch self { case .white:"#1A1A1A"; case .sepia:"#3B2A1A"; case .dark:"#E5E5E7"; case .night:"#CCCCCC" } }
    var uiBG: Color   { switch self {
        case .white: .white;                case .sepia: Color(hex: "#F5EDD6")
        case .dark:  Color(hex: "#1C1C1E"); case .night: .black
    }}
    var isDark: Bool { self == .dark || self == .night }
}

enum ReaderFont: String, CaseIterable {
    case system, serif, rounded
    var label: String { switch self { case .system:"系统"; case .serif:"衬线"; case .rounded:"圆润" } }
    var css: String { switch self {
        case .system:  "-apple-system,'PingFang SC',sans-serif"
        case .serif:   "Georgia,'Songti SC',STSong,serif"
        case .rounded: "'SF Pro Rounded','PingFang SC',sans-serif"
    }}
}

// MARK: - Controller
// Uses CSS multi-column layout (column-width = viewW) so content flows into
// horizontal pages automatically.  We scroll contentOffset.x to navigate.
// The wrapper div (#__lbb_w__) carries the horizontal text-padding so each
// column is exactly viewW wide and the text has 22 pt margin on each side.

@MainActor
class ReaderController: ObservableObject {

    // MARK: Chapter state
    @Published var chapterIndex: Int = 0
    var spineItems: [EPUBExtractor.SpineItem] = []
    var extractDir: URL? = nil

    // MARK: WebView
    weak var webView: WKWebView?
    private var preloadWebView: WKWebView?
    private var preloadChapterIndex: Int = -1

    // MARK: Page state
    @Published var currentPage: Int  = 1
    @Published var totalPages:  Int  = 1
    @Published var showControls: Bool = true

    // MARK: Layout (set by GeometryReader before first CSS injection)
    var availableWidth:  Double = 0
    var availableHeight: Double = 0

    // MARK: Drag state
    private var isDragging:     Bool    = false
    private var dragOriginPage: Int     = 1
    private var dragOriginX:    CGFloat = 0   // exact contentOffset.x at drag start
    private var isTransitioning: Bool   = false

    // MARK: Book-level page tracking
    private var chapterPageCounts: [Int: Int] = [:]

    var currentBookPage: Int {
        let prev = (0..<chapterIndex).compactMap { chapterPageCounts[$0] }.reduce(0, +)
        return prev + currentPage
    }
    var totalBookPages: Int {
        let known = chapterPageCounts
        let sum = known.values.reduce(0, +); let cnt = known.count
        let total = spineItems.count
        if cnt == 0 { return max(totalPages, 1) }
        let avg = max(1, sum / cnt)
        return (0..<total).map { known[$0] ?? avg }.reduce(0, +)
    }

    // MARK: - Gesture

    func handlePanChanged(dx: CGFloat, dy: CGFloat) {
        guard abs(dx) > abs(dy) * 0.7 else { return }
        guard !isTransitioning, availableWidth > 0 else { return }
        guard let wv = webView else { return }

        if !isDragging {
            isDragging     = true
            dragOriginX    = wv.scrollView.contentOffset.x   // actual position, not page-snapped
            dragOriginPage = max(1, min(totalPages, Int(dragOriginX / CGFloat(availableWidth)) + 1))
        }

        let maxX    = CGFloat(Double(totalPages - 1) * availableWidth)
        let rawX    = dragOriginX - dx
        let newX: CGFloat

        if rawX < 0 {
            newX = rawX * 0.25          // rubber-band left boundary
        } else if rawX > maxX {
            newX = maxX + (rawX - maxX) * 0.25  // rubber-band right boundary
        } else {
            newX = rawX
        }
        wv.scrollView.setContentOffset(CGPoint(x: newX, y: 0), animated: false)
    }

    func handlePanEnded(dx: CGFloat, velocityX: CGFloat) {
        guard isDragging else { return }
        isDragging = false

        let vW = availableWidth
        guard vW > 0 else { return }

        // Decide whether to complete the page turn
        let predictedX = dx + velocityX * 0.12
        let complete   = abs(dx) > vW * 0.3 || abs(predictedX) > vW * 0.45

        if complete {
            if dx < 0 {   // forward
                if dragOriginPage < totalPages {
                    snapToPage(dragOriginPage + 1, velocityX: velocityX)
                } else if chapterIndex < spineItems.count - 1 {
                    advanceChapter(forward: true)
                } else {
                    snapToPage(dragOriginPage, velocityX: velocityX)
                }
            } else {      // backward
                if dragOriginPage > 1 {
                    snapToPage(dragOriginPage - 1, velocityX: velocityX)
                } else if chapterIndex > 0 {
                    advanceChapter(forward: false)
                } else {
                    snapToPage(dragOriginPage, velocityX: velocityX)
                }
            }
        } else {
            snapToPage(dragOriginPage, velocityX: velocityX)
        }
    }

    func handlePanCancelled() {
        guard isDragging else { return }
        isDragging = false
        snapToPage(dragOriginPage)
    }

    func handleTap() { showControls.toggle() }

    // MARK: - Button page turn

    func triggerPageTurn(direction: Int) {
        let target = currentPage + direction
        if target >= 1, target <= totalPages { snapToPage(target) }
    }

    // MARK: - Snap (UIKit spring, very smooth, respects finger velocity)

    func snapToPage(_ page: Int, velocityX: CGFloat = 0) {
        guard let wv = webView, availableWidth > 0 else { return }
        let target  = max(1, min(page, totalPages))
        let targetX = CGFloat(Double(target - 1) * availableWidth)
        // Normalised velocity: how many pages per second the finger was moving
        let normVel = abs(velocityX) / CGFloat(availableWidth)

        UIView.animate(
            withDuration: 0.32, delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: min(normVel, 8),
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            wv.scrollView.contentOffset.x = targetX
        }
        currentPage = target
    }

    private func advanceChapter(forward: Bool) {
        guard !isTransitioning else { return }
        isTransitioning = true
        chapterIndex = forward
            ? min(chapterIndex + 1, spineItems.count - 1)
            : max(chapterIndex - 1, 0)
        currentPage = 1; totalPages = 1
        isTransitioning = false
    }

    // MARK: - Page ops

    func jumpToPage(_ page: Int) {
        guard let wv = webView, availableWidth > 0 else { return }
        let target = max(1, min(page, totalPages))
        wv.scrollView.setContentOffset(
            CGPoint(x: CGFloat(Double(target - 1) * availableWidth), y: 0),
            animated: false)
        currentPage = target
    }

    func recomputePages(retryCount: Int = 0) {
        guard let wv = webView, availableWidth > 10 else {
            guard retryCount < 10 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.recomputePages(retryCount: retryCount + 1)
            }
            return
        }
        let vW = availableWidth

        // body.scrollWidth = total rendered width of all columns = numPages * viewW
        wv.evaluateJavaScript("""
            (function(vW){
                var sw = document.body ? (document.body.scrollWidth || 0) : 0;
                if (sw < vW * 0.8) return '';
                var total = Math.max(1, Math.round(sw / vW));
                var curX  = Math.round(
                    window.pageXOffset
                    || (document.documentElement ? document.documentElement.scrollLeft : 0)
                    || (document.body ? document.body.scrollLeft : 0) || 0);
                var cur = Math.max(1, Math.min(total, Math.round(curX / vW) + 1));
                return total + '|' + cur;
            })(\(vW))
        """) { [weak self] res, _ in
            guard let self else { return }
            if let s = res as? String, !s.isEmpty {
                let p = s.split(separator: "|").compactMap { Double($0) }
                if p.count >= 1, p[0] >= 1 {
                    let newTotal = max(1, Int(p[0]))
                    let newPage  = p.count > 1 ? max(1, min(newTotal, Int(p[1]))) : 1
                    self.totalPages  = newTotal
                    self.currentPage = newPage
                    self.chapterPageCounts[self.chapterIndex] = newTotal
                    self.webView?.scrollView.setContentOffset(
                        CGPoint(x: CGFloat(Double(newPage - 1) * self.availableWidth), y: 0),
                        animated: false)
                    return
                }
            }
            guard retryCount < 14 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.recomputePages(retryCount: retryCount + 1)
            }
        }
    }

    func reset() { currentPage = 1; totalPages = 1 }

    // MARK: - Preload next chapter

    func preloadNextChapter(settings: ReaderSettings) {
        let nextIdx = chapterIndex + 1
        guard nextIdx < spineItems.count,
              nextIdx != preloadChapterIndex,
              let dir = extractDir else { return }
        preloadChapterIndex = nextIdx
        if preloadWebView == nil {
            let cfg = WKWebViewConfiguration()
            cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
            let wv = WKWebView(frame: CGRect(x: -2000, y: 0, width: 390, height: 844),
                               configuration: cfg)
            wv.scrollView.contentInsetAdjustmentBehavior = .never
            preloadWebView = wv
        }
        preloadWebView?.loadFileURL(spineItems[nextIdx].url, allowingReadAccessTo: dir)
    }
}

// MARK: - Gesture Overlay

private struct GestureOverlayView: UIViewRepresentable {
    let controller: ReaderController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> HitView {
        let v = HitView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        tap.require(toFail: pan)
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ uiView: HitView, context: Context) {}

    final class HitView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            bounds.contains(point)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let controller: ReaderController
        init(controller: ReaderController) { self.controller = controller }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let v = gr.view else { return }
            let t   = gr.translation(in: v)
            let vel = gr.velocity(in: v)
            switch gr.state {
            case .began, .changed:
                controller.handlePanChanged(dx: t.x, dy: t.y)
            case .ended:
                controller.handlePanEnded(dx: t.x, velocityX: vel.x)
            case .cancelled, .failed:
                controller.handlePanCancelled()
            default: break
            }
        }

        @objc func handleTap() { controller.handleTap() }

        func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
            guard let pan = gr as? UIPanGestureRecognizer, let v = pan.view else { return true }
            let vel = pan.velocity(in: v)
            return abs(vel.x) > abs(vel.y) * 0.8
        }

        func gestureRecognizer(_ gr: UIGestureRecognizer,
                                shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }
    }
}

// MARK: - Main View

struct EPUBReaderView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @Binding var book: Book

    @StateObject private var settings   = ReaderSettings()
    @StateObject private var controller = ReaderController()

    @State private var showSettings = false
    @State private var loadError:   String? = nil

    private var chapterURL: URL? {
        controller.spineItems[safe: controller.chapterIndex]?.url
    }

    var body: some View {
        ZStack {
            settings.theme.uiBG.ignoresSafeArea()

            if loadError != nil {
                errorView
            } else if controller.spineItems.isEmpty {
                loadingView
            } else {
                VStack(spacing: 0) {
                    topBar
                        .opacity(controller.showControls ? 1 : 0)
                        .allowsHitTesting(controller.showControls)
                    webSlot
                    bottomBar
                        .opacity(controller.showControls ? 1 : 0)
                        .allowsHitTesting(controller.showControls)
                }
                .animation(.easeInOut(duration: 0.22), value: controller.showControls)
            }
        }
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
        .task { await loadBook() }
        .onDisappear { save() }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel(settings: settings, onChanged: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    controller.recomputePages()
                }
            })
            .presentationDetents([.height(310)])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: controller.chapterIndex) { _ in
            controller.preloadNextChapter(settings: settings)
        }
    }

    // ── Top bar ───────────────────────────────────────────────────────────────

    private var topBar: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let t = controller.spineItems[safe: controller.chapterIndex]?.title {
                    Text(t).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // ── Bottom bar ────────────────────────────────────────────────────────────

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button { goPrev() } label: {
                Image(systemName: "chevron.left").font(.system(size: 14))
                    .frame(width: 48, height: 38)
                    .foregroundStyle(canGoPrev ? .primary : .quaternary)
            }.disabled(!canGoPrev)
            Spacer()
            Text("\(controller.currentBookPage) / \(controller.totalBookPages)")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
            Spacer()
            Button { goNext() } label: {
                Image(systemName: "chevron.right").font(.system(size: 14))
                    .frame(width: 48, height: 38)
                    .foregroundStyle(canGoNext ? .primary : .quaternary)
            }.disabled(!canGoNext)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    // ── Web slot ──────────────────────────────────────────────────────────────

    @ViewBuilder
    private var webSlot: some View {
        GeometryReader { geo in
            let fW = geo.size.width
            let fH = geo.size.height
            ZStack {
                if let url = chapterURL, let dir = controller.extractDir {
                    ReaderWebView(fileURL: url, extractDir: dir,
                                  settings: settings, controller: controller)
                        .frame(width: fW, height: fH)
                } else {
                    loadingView
                }
                GestureOverlayView(controller: controller)
                    .frame(width: fW, height: fH)
            }
            .clipped()
            .onAppear {
                controller.availableWidth  = Double(fW)
                controller.availableHeight = Double(fH)
            }
            .onChange(of: fH) { v in
                controller.availableHeight = Double(v)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { controller.recomputePages() }
            }
            .onChange(of: fW) { v in
                controller.availableWidth = Double(v)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { controller.recomputePages() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Navigation ────────────────────────────────────────────────────────────

    private func goNext() {
        if controller.currentPage < controller.totalPages {
            controller.triggerPageTurn(direction: +1)
        } else if controller.chapterIndex < controller.spineItems.count - 1 {
            controller.chapterIndex += 1; controller.reset()
        }
    }

    private func goPrev() {
        if controller.currentPage > 1 {
            controller.triggerPageTurn(direction: -1)
        } else if controller.chapterIndex > 0 {
            controller.chapterIndex -= 1; controller.reset()
        }
    }

    private var canGoPrev: Bool { controller.currentPage > 1 || controller.chapterIndex > 0 }
    private var canGoNext: Bool {
        controller.currentPage < controller.totalPages
            || controller.chapterIndex < controller.spineItems.count - 1
    }

    // ── Utility ───────────────────────────────────────────────────────────────

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在加载…").font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text(loadError ?? "加载失败").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("返回") { dismiss() }.buttonStyle(.borderedProminent)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadBook() async {
        do {
            let r = try await Task.detached(priority: .userInitiated) {
                try EPUBExtractor.extract(book: self.book)
            }.value
            await MainActor.run {
                controller.extractDir  = r.extractDir
                controller.spineItems  = r.spineItems
                let n = r.spineItems.count
                if n > 0 {
                    let per = 1.0 / Double(n)
                    controller.chapterIndex = max(0, min(n - 1, Int(book.readingProgress / per)))
                }
                controller.preloadNextChapter(settings: settings)
            }
        } catch {
            await MainActor.run { loadError = error.localizedDescription }
        }
    }

    private func save() {
        var b = book
        let n   = controller.spineItems.count
        let per = n > 0 ? 1.0 / Double(n) : 1.0
        let pg  = controller.totalPages > 1
            ? Double(controller.currentPage - 1) / Double(controller.totalPages - 1) : 0
        b.readingProgress = Double(controller.chapterIndex) * per + pg * per
        b.lastReadDate    = Date()
        store.updateBook(b); book = b
    }
}

// MARK: - WKWebView Wrapper
//
// CSS multi-column strategy:
//   • body: no horizontal padding, column-width = viewW, height = viewH
//     → each column is exactly viewW wide; columns overflow to the right
//   • #__lbb_w__ (wrapper div injected once via JS):
//     padding: 0 22px → text has 22 pt margin inside every column
//   • WKWebView.scrollView.contentOffset.x = (page-1) * viewW

struct ReaderWebView: UIViewRepresentable {
    let fileURL:    URL
    let extractDir: URL
    @ObservedObject var settings:   ReaderSettings
    @ObservedObject var controller: ReaderController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.scrollView.showsVerticalScrollIndicator   = false
        wv.scrollView.showsHorizontalScrollIndicator = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.bounces                = false
        wv.scrollView.alwaysBounceVertical   = false
        wv.scrollView.alwaysBounceHorizontal = false
        // Our GestureOverlayView owns all panning
        wv.scrollView.panGestureRecognizer.isEnabled = false
        wv.isOpaque        = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear

        context.coordinator.wv = wv
        controller.webView      = wv
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        let c = context.coordinator
        if c.lastURL != fileURL {
            c.lastURL          = fileURL
            c.lastSettingsHash = settingsHash
            controller.webView = wv
            wv.loadFileURL(fileURL, allowingReadAccessTo: extractDir)
        } else {
            let h = settingsHash
            guard c.lastSettingsHash != h else { return }
            c.lastSettingsHash = h
            // Re-inject CSS; wrapper div is already present (idempotent check inside JS)
            wv.evaluateJavaScript(cssJS(), completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { controller.recomputePages() }
        }
    }

    private var settingsHash: String {
        "\(Int(settings.fontSize))-\(settings.themeRaw)-\(settings.fontRaw)"
    }

    func cssJS() -> String {
        let vW = Int(controller.availableWidth)
        let vH = Int(controller.availableHeight)
        guard vW > 10, vH > 10 else { return "(function(){})()" }

        let vPad    = 24          // top / bottom padding inside the column
        let hPad    = 22          // horizontal padding per side (inside wrapper div)
        let maxImgH = Int(Double(vH - vPad * 2) * 0.85)

        return """
        (function(){
          // ① viewport meta
          if (!document.querySelector('meta[name=viewport]')) {
            var m = document.createElement('meta');
            m.name    = 'viewport';
            m.content = 'width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no';
            document.head && document.head.appendChild(m);
          }

          // ② Inject wrapper div ONCE so horizontal padding lives inside each column,
          //   not on the body (which would break column-width alignment).
          if (!document.getElementById('__lbb_w__')) {
            var w = document.createElement('div');
            w.id  = '__lbb_w__';
            var b = document.body;
            var kids = Array.prototype.slice.call(b.childNodes);
            for (var i = 0; i < kids.length; i++) { w.appendChild(kids[i]); }
            b.appendChild(w);
          }

          // ③ Style sheet
          var s = document.getElementById('__lbb__');
          if (!s) { s = document.createElement('style'); s.id = '__lbb__';
                    document.head && document.head.appendChild(s); }
          s.textContent = `
            html {
              height: \(vH)px !important;
              overflow-y: hidden !important;
              -webkit-text-size-adjust: none !important;
            }
            body {
              margin: 0 !important;
              /* NO horizontal padding — column-width must equal full viewW */
              padding: \(vPad)px 0 \(vPad)px !important;
              height: \(vH)px !important;
              overflow-y: hidden !important;
              overflow-x: visible !important;
              /* Multi-column: each column = full viewport width */
              -webkit-column-width: \(vW)px !important;
              -webkit-column-gap: 0px !important;
              column-width: \(vW)px !important;
              column-gap: 0px !important;
              column-fill: auto !important;
              /* Typography */
              font-family: \(settings.font.css) !important;
              font-size: \(Int(settings.fontSize))px !important;
              line-height: 1.85 !important;
              word-break: break-word !important;
              background: \(settings.theme.bg) !important;
              color: \(settings.theme.fg) !important;
            }
            html, body {
              background: \(settings.theme.bg) !important;
              color: \(settings.theme.fg) !important;
            }
            /* Wrapper carries horizontal padding inside every column */
            #__lbb_w__ {
              padding: 0 \(hPad)px !important;
              box-sizing: border-box !important;
              display: block !important;
            }
            *, *::before, *::after { box-sizing: border-box !important; }
            p, li, td, th, span,
            h1, h2, h3, h4, h5, h6 { color: \(settings.theme.fg) !important; }
            img {
              max-width: 100% !important;
              max-height: \(maxImgH)px !important;
              height: auto !important;
              display: block !important;
              margin: 0.5em auto !important;
              break-inside: avoid !important;
              -webkit-column-break-inside: avoid !important;
            }
            a   { color: #4A90E2 !important; text-decoration: none !important; }
            p   { margin: 0 0 0.85em !important; text-indent: 2em !important; }
            h1, h2, h3, h4 {
              font-weight: 700 !important;
              margin: 0.9em 0 0.4em !important;
              text-indent: 0 !important;
            }
            table { width: 100% !important; border-collapse: collapse !important; }
            td, th { padding: 4px 8px !important; }
          `;
        })();
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent:           ReaderWebView
        weak var wv:          WKWebView?
        var lastURL:          URL?
        var lastSettingsHash: String = ""

        init(_ p: ReaderWebView) { parent = p }

        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
            self.wv = wv
            parent.controller.webView = wv
            // Inject immediately; re-inject after fonts / images settle
            wv.evaluateJavaScript(parent.cssJS(), completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak wv, weak self] in
                guard let wv, let self else { return }
                wv.evaluateJavaScript(self.parent.cssJS(), completionHandler: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.parent.controller.recomputePages()
                }
            }
        }

        func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError e: Error) {
            print("[Reader] didFail:", e.localizedDescription)
        }
        func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!,
                     withError e: Error) {
            print("[Reader] provisional:", e.localizedDescription)
        }
    }
}

// MARK: - Settings Panel

struct ReaderSettingsPanel: View {
    @ObservedObject var settings: ReaderSettings
    var onChanged: (() -> Void)? = nil
    private let sizes: [Double] = [14, 16, 18, 20, 22, 24, 26]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule().fill(Color(.tertiaryLabel)).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Text("阅读设置").font(.headline).frame(maxWidth: .infinity, alignment: .center)

            sectionHeader("字体大小", icon: "textformat.size")
            HStack(spacing: 6) {
                stepBtn(icon: "minus") { step(-1) }.disabled(settings.fontSize <= sizes.first!)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(sizes, id: \.self) { s in
                        Button { settings.fontSize = s; onChanged?() } label: {
                            Text("\(Int(s))")
                                .font(.system(size: 11,
                                              weight: settings.fontSize == s ? .bold : .regular))
                                .frame(width: 31, height: 31)
                                .background(settings.fontSize == s
                                            ? Color.accentColor : Color(.tertiarySystemFill))
                                .foregroundStyle(settings.fontSize == s ? .white : .primary)
                                .clipShape(Circle())
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                stepBtn(icon: "plus") { step(+1) }.disabled(settings.fontSize >= sizes.last!)
            }

            sectionHeader("主题背景", icon: "circle.lefthalf.filled")
            HStack(spacing: 0) {
                ForEach(ReaderTheme.allCases, id: \.self) { t in
                    Button { settings.theme = t; onChanged?() } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(Color(hex: t.bg)).frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(
                                        settings.theme == t ? Color.accentColor : Color(.separator),
                                        lineWidth: settings.theme == t ? 2.5 : 1))
                                Text("文").font(.system(size: 13))
                                    .foregroundColor(Color(hex: t.fg))
                            }
                            Text(t.label).font(.system(size: 10))
                                .foregroundStyle(settings.theme == t ? Color.accentColor : .secondary)
                        }
                    }.buttonStyle(.plain).frame(maxWidth: .infinity)
                }
            }

            sectionHeader("字体", icon: "character")
            HStack(spacing: 8) {
                ForEach(ReaderFont.allCases, id: \.self) { f in
                    Button { settings.font = f; onChanged?() } label: {
                        Text(f.label).font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(settings.font == f
                                        ? Color.accentColor : Color(.tertiarySystemFill))
                            .foregroundStyle(settings.font == f ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
    }

    private func stepBtn(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14))
                .frame(width: 34, height: 30)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }

    private func step(_ d: Int) {
        guard let i = sizes.firstIndex(of: settings.fontSize),
              sizes.indices.contains(i + d) else { return }
        settings.fontSize = sizes[i + d]; onChanged?()
    }
}

// MARK: - Array helper

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
