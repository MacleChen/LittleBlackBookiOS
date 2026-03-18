import SwiftUI
import WebKit
import ZIPFoundation

// MARK: - Settings

class ReaderSettings: ObservableObject {
    @AppStorage("r_fontSize")   var fontSize:   Double = 18
    @AppStorage("r_lineHeight") var lineHeight: Double = 1.6
    @AppStorage("r_theme")      var themeRaw:   String = ReaderTheme.white.rawValue
    @AppStorage("r_font")       var fontRaw:    String = ReaderFont.system.rawValue
    var theme: ReaderTheme { get { .init(rawValue: themeRaw) ?? .white } set { themeRaw = newValue.rawValue } }
    var font:  ReaderFont  { get { .init(rawValue: fontRaw)  ?? .system } set { fontRaw  = newValue.rawValue } }

    // CSS for horizontal column-paginated layout.
    // Uses viewport units (100vw / 100vh) so layout always matches the
    // WKWebView's actual frame — no hardcoded screen dimensions needed.
    var css: String {
        let family: String
        switch font {
        case .system:  family = "-apple-system, 'PingFang SC', sans-serif"
        case .serif:   family = "Georgia, 'Songti SC', 'SimSun', serif"
        case .rounded: family = "-apple-system, 'PingFang SC', sans-serif"
        }
        let lh = lineHeight
        return """
        html {
          margin: 0; padding: 0;
          width: 100vw; height: 100vh;
          overflow: hidden;
        }
        body {
          margin: 0; padding: 0;
          height: 100vh;
          overflow: visible;
          -webkit-column-fill: auto; column-fill: auto;
          -webkit-column-width: 100vw; column-width: 100vw;
          -webkit-column-gap: 0; column-gap: 0;
          font-size: \(Int(fontSize))px;
          line-height: \(lh) !important;
          font-family: \(family);
          color: \(theme.fg);
          background-color: \(theme.bg);
          word-wrap: break-word; overflow-wrap: break-word;
        }
        body * { line-height: \(lh) !important; }
        img { max-width: 100% !important; height: auto !important;
              display: block; margin: 0 auto; }
        a   { color: \(theme.fg); }
        *   { box-sizing: border-box; }
        """
    }
}

enum ReaderTheme: String, CaseIterable {
    case white, sepia, dark, night
    var label: String { switch self { case .white:"白天"; case .sepia:"护眼"; case .dark:"深色"; case .night:"夜间" } }
    var bg: String    { switch self { case .white:"#FFFFFF"; case .sepia:"#F5EDD6"; case .dark:"#1C1C1E"; case .night:"#000000" } }
    var fg: String    { switch self { case .white:"#1A1A1A"; case .sepia:"#3B2A1A"; case .dark:"#E5E5E7"; case .night:"#CCCCCC" } }
    var uiBG: Color { switch self {
        case .white: .white;                case .sepia: Color(hex: "#F5EDD6")
        case .dark:  Color(hex: "#1C1C1E"); case .night: .black
    }}
    var isDark: Bool { self == .dark || self == .night }
}

enum ReaderFont: String, CaseIterable {
    case system, serif, rounded
    var label: String { switch self { case .system:"系统"; case .serif:"衬线"; case .rounded:"圆润" } }
}

// MARK: - Weak message handler wrapper

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { self.target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

// MARK: - Paginated Reader ViewController

final class PaginatedReaderVC: UIViewController,
                                WKNavigationDelegate,
                                WKScriptMessageHandler,
                                UIScrollViewDelegate {

    // Callbacks
    var onTap:             (() -> Void)?
    var onPageUpdate:      ((Int, Int) -> Void)?   // (current, total)
    var onChapterBoundary: ((Int) -> Void)?        // delta: +1 or -1

    // State
    private(set) var webView: WKWebView!
    private var chapterURL:    URL?
    private var rootDir:       URL?
    private var pendingCSS:    String = ""
    private var startAtEnd:    Bool   = false

    private var totalPageCount   = 1
    private var currentPageIndex = 0   // 0-based
    private var pageWidth: CGFloat { webView?.scrollView.frame.width ?? UIScreen.main.bounds.width }

    var bgColor: UIColor = .white {
        didSet {
            view.backgroundColor               = bgColor
            webView?.backgroundColor           = bgColor
            webView?.scrollView.backgroundColor = bgColor
        }
    }

    // MARK: - Setup

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Re-query page count whenever the frame settles (covers initial layout
        // and any safe-area / orientation changes)
        guard isViewLoaded, chapterURL != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.queryPageCount()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bgColor

        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptHandler(self), name: "pagesReady")

        let wv = WKWebView(frame: view.bounds, configuration: config)
        wv.autoresizingMask              = [.flexibleWidth, .flexibleHeight]
        wv.navigationDelegate            = self
        wv.isOpaque                      = false
        wv.backgroundColor               = bgColor
        wv.scrollView.backgroundColor    = bgColor
        wv.scrollView.isPagingEnabled    = true
        wv.scrollView.bounces            = false
        wv.scrollView.alwaysBounceVertical   = false
        wv.scrollView.alwaysBounceHorizontal = false
        wv.scrollView.showsHorizontalScrollIndicator = false
        wv.scrollView.showsVerticalScrollIndicator   = false
        wv.scrollView.delegate           = self
        view.addSubview(wv)
        self.webView = wv

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        tap.cancelsTouchesInView = false
        wv.addGestureRecognizer(tap)

        if chapterURL != nil { loadContent() }
    }

    // MARK: - Public API

    func loadChapter(url: URL, rootDir: URL, css: String, startAtEnd: Bool = false) {
        self.chapterURL = url
        self.rootDir    = rootDir
        self.pendingCSS = css
        self.startAtEnd = startAtEnd
        currentPageIndex = 0
        totalPageCount   = 1
        if isViewLoaded { loadContent() }
    }

    func updateCSS(_ css: String, bgColor: UIColor? = nil) {
        pendingCSS = css
        if let bg = bgColor { self.bgColor = bg }
        guard isViewLoaded else { return }
        // Reset html width so it can be remeasured with new layout
        webView.evaluateJavaScript(
            "document.documentElement.style.width = '';", completionHandler: nil)
        injectCSS()
        // Re-query page count after CSS update (layout may have changed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.queryPageCount()
        }
    }

    // MARK: - Private

    private func loadContent() {
        guard let url = chapterURL, let root = rootDir else { return }
        webView.scrollView.setContentOffset(.zero, animated: false)
        webView.loadFileURL(url, allowingReadAccessTo: root)
    }

    private func injectCSS() {
        let esc = pendingCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'",  with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = """
        (function(){
          // Ensure viewport = device-width so 100vw == WKWebView frame width
          var mv = document.querySelector('meta[name="viewport"]');
          if (!mv) {
            mv = document.createElement('meta');
            mv.name = 'viewport';
            (document.head || document.documentElement).insertBefore(mv, null);
          }
          mv.setAttribute('content',
            'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');

          // Inject reader CSS
          var e = document.getElementById('_rs'); if (e) e.remove();
          var s = document.createElement('style'); s.id = '_rs';
          s.textContent = '\(esc)';
          (document.head || document.documentElement).appendChild(s);

          // Strip inline line-height overrides so our CSS !important takes effect
          document.querySelectorAll('*').forEach(function(el) {
            if (el.style && el.style.lineHeight) el.style.lineHeight = '';
          });

          // Wrap body children in a padded div for visual margins
          // (body itself must have padding:0 so CSS columns align with isPagingEnabled)
          var pw = document.getElementById('_pw');
          if (!pw) {
            pw = document.createElement('div');
            pw.id = '_pw';
            pw.style.cssText = 'padding: 20px 18px 36px; box-sizing: border-box;';
            while (document.body.firstChild) { pw.appendChild(document.body.firstChild); }
            document.body.appendChild(pw);
          }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // Ask the WebView how many columns (pages) the content has after layout.
    // Key: body has overflow:visible so body.scrollWidth = N * viewportWidth.
    // We expand the html element to that width so WKWebView's scrollView.contentSize
    // becomes N pages wide — this is what makes isPagingEnabled work.
    // Retries up to 6x (150ms apart) waiting for CSS column layout to settle.
    private func queryPageCount() {
        let js = """
        (function doMeasure(n) {
          var vw = window.innerWidth || 1;
          var sw = document.body.scrollWidth || vw;
          if (sw > vw) {
            // Expand html element so WKWebView.scrollView.contentSize covers all pages
            document.documentElement.style.width = sw + 'px';
            var total = Math.max(1, Math.round(sw / vw));
            window.webkit.messageHandlers.pagesReady.postMessage({total: total});
            return;
          }
          if (n <= 0) {
            window.webkit.messageHandlers.pagesReady.postMessage({total: 1});
            return;
          }
          setTimeout(function(){ doMeasure(n - 1); }, 150);
        })(6);
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectCSS()
        // Wait for CSS column layout to settle before measuring pages
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.queryPageCount()
        }
    }

    // WKScriptMessageHandler — receives total page count from JS
    func userContentController(_ controller: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard message.name == "pagesReady",
              let body  = message.body as? [String: Any],
              let total = body["total"] as? Int else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.totalPageCount = max(1, total)
            if self.startAtEnd {
                self.startAtEnd = false
                let lastPage = self.totalPageCount - 1
                let offset = CGFloat(lastPage) * self.pageWidth
                self.webView.scrollView.setContentOffset(
                    CGPoint(x: offset, y: 0), animated: false)
                self.currentPageIndex = lastPage
            }
            self.onPageUpdate?(self.currentPageIndex + 1, self.totalPageCount)
        }
    }

    // UIScrollViewDelegate — track current page while scrolling
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard pageWidth > 0 else { return }
        let page = Int(scrollView.contentOffset.x / pageWidth)
        let clamped = max(0, min(page, totalPageCount - 1))
        if clamped != currentPageIndex {
            currentPageIndex = clamped
            onPageUpdate?(currentPageIndex + 1, totalPageCount)
        }
    }

    // UIScrollViewDelegate — detect chapter-boundary swipe
    func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                   withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard pageWidth > 0 else { return }
        let targetPage = Int(round(targetContentOffset.pointee.x / pageWidth))

        if velocity.x > 0 && currentPageIndex >= totalPageCount - 1 {
            // Swiping forward past last page → request next chapter
            DispatchQueue.main.async { self.onChapterBoundary?(+1) }
        } else if velocity.x < 0 && currentPageIndex <= 0 && targetPage <= 0 {
            // Swiping backward past first page → request prev chapter
            DispatchQueue.main.async { self.onChapterBoundary?(-1) }
        }
    }

    // MARK: - Programmatic page navigation

    func goToNextPage() {
        guard let wv = webView else { return }
        if currentPageIndex < totalPageCount - 1 {
            let offset = CGFloat(currentPageIndex + 1) * pageWidth
            wv.scrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: true)
        } else {
            onChapterBoundary?(+1)
        }
    }

    func goToPrevPage() {
        guard let wv = webView else { return }
        if currentPageIndex > 0 {
            let offset = CGFloat(currentPageIndex - 1) * pageWidth
            wv.scrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: true)
        } else {
            onChapterBoundary?(-1)
        }
    }

    @objc private func didTap(_ r: UITapGestureRecognizer) {
        let x = r.location(in: view).x
        let w = view.bounds.width
        if x < w / 3 {
            goToPrevPage()
        } else if x > w * 2 / 3 {
            goToNextPage()
        } else {
            onTap?()
        }
    }
}

// MARK: - UIViewControllerRepresentable

struct PaginatedReaderView: UIViewControllerRepresentable {
    @Binding var chapterIndex: Int
    let spineURLs:     [URL]
    let rootDir:       URL
    let settings:      ReaderSettings
    let bgColor:       UIColor
    var onTap:         () -> Void
    var onPageUpdate:  (Int, Int) -> Void
    var onChapterChange: (Int) -> Void   // absolute new chapter index

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PaginatedReaderVC {
        let vc  = PaginatedReaderVC()
        let coord = context.coordinator
        vc.bgColor       = bgColor
        vc.onTap         = onTap
        vc.onPageUpdate  = onPageUpdate
        vc.onChapterBoundary = { delta in
            let newIdx = coord.parent.chapterIndex + delta
            guard newIdx >= 0 && newIdx < coord.parent.spineURLs.count else { return }
            coord.parent.onChapterChange(newIdx)
        }
        coord.vc                 = vc
        coord.loadedChapterIndex = chapterIndex
        vc.loadChapter(url: spineURLs[chapterIndex],
                       rootDir: rootDir,
                       css: settings.css)
        return vc
    }

    func updateUIViewController(_ vc: PaginatedReaderVC, context: Context) {
        context.coordinator.parent = self

        // CSS / theme changed
        vc.updateCSS(settings.css, bgColor: bgColor)

        // Chapter changed externally (bottom bar buttons)
        let coord = context.coordinator
        guard coord.loadedChapterIndex != chapterIndex else { return }
        let goBack = chapterIndex < coord.loadedChapterIndex
        coord.loadedChapterIndex = chapterIndex
        vc.loadChapter(url: spineURLs[chapterIndex],
                       rootDir: rootDir,
                       css: settings.css,
                       startAtEnd: goBack)
    }

    final class Coordinator {
        var parent: PaginatedReaderView
        weak var vc: PaginatedReaderVC?
        var loadedChapterIndex: Int

        init(_ p: PaginatedReaderView) {
            self.parent             = p
            self.loadedChapterIndex = p.chapterIndex
        }
    }
}

// MARK: - Main Reader View

struct EPUBReaderView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @Binding var book: Book

    @StateObject private var settings = ReaderSettings()

    @State private var spineURLs:      [URL] = []
    @State private var tempDir:        URL?
    @State private var chapterIndex:   Int = 0
    @State private var loadError:      String?
    @State private var showControls:   Bool = true
    @State private var showSettings:   Bool = false
    @State private var showCompletion: Bool = false
    @State private var currentPage:    Int = 1
    @State private var totalPages:     Int = 1

    private var totalChapters: Int { spineURLs.count }
    private var overallProgress: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(chapterIndex) / Double(totalChapters)
    }

    var body: some View {
        ZStack {
            settings.theme.uiBG.ignoresSafeArea()

            if let error = loadError {
                errorView(error)
            } else if !spineURLs.isEmpty, let dir = tempDir {
                VStack(spacing: 0) {
                    topBar
                        .opacity(showControls ? 1 : 0)
                        .allowsHitTesting(showControls)

                    PaginatedReaderView(
                        chapterIndex: $chapterIndex,
                        spineURLs:   spineURLs,
                        rootDir:     dir,
                        settings:    settings,
                        bgColor:     UIColor(settings.theme.uiBG),
                        onTap:       { showControls.toggle() },
                        onPageUpdate: { cur, tot in
                            currentPage = cur
                            totalPages  = tot
                        },
                        onChapterChange: { newIdx in
                            if newIdx < totalChapters {
                                chapterIndex = newIdx
                                currentPage  = 1
                                totalPages   = 1
                            } else {
                                showCompletion = true
                            }
                        }
                    )

                    bottomBar
                        .opacity(showControls ? 1 : 0)
                        .allowsHitTesting(showControls)
                }
                .animation(.easeInOut(duration: 0.22), value: showControls)
            } else {
                loadingView
            }
        }
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
        .task { await loadBook() }
        .onDisappear { saveProgress(); cleanupTemp() }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel(settings: settings)
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCompletion) {
            BookCompletionSheet(bookTitle: book.title, existingNotes: book.notes) { notes in
                finishBook(notes: notes)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            Text(book.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
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

    // MARK: - Bottom bar  (page counter only)

    private var bottomBar: some View {
        Text("\(currentPage) / \(totalPages)")
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
    }

    // MARK: - Utility views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在加载…").font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text(msg).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("返回") { dismiss() }.buttonStyle(.borderedProminent)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load book

    private func loadBook() async {
        do {
            guard FileManager.default.fileExists(atPath: book.fileURL.path) else {
                await MainActor.run { loadError = "书籍文件不存在，请重新导入" }
                return
            }
            guard isZIPFile(at: book.fileURL) else {
                await MainActor.run { loadError = "书籍文件格式不受支持或已损坏（非 EPUB/ZIP）" }
                return
            }

            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("epub_\(book.id)_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            try extractArchive(from: book.fileURL, to: temp)

            let spine = try EPUBMetadataParser.extractSpine(from: temp)
            guard !spine.isEmpty else {
                await MainActor.run { loadError = "无法解析书籍目录结构，EPUB 格式可能不标准" }
                return
            }

            let saved = UserDefaults.standard.integer(forKey: "chapter_\(book.id)")
            let start = max(0, min(saved, spine.count - 1))

            await MainActor.run {
                tempDir      = temp
                spineURLs    = spine
                chapterIndex = start
            }
        } catch {
            await MainActor.run { loadError = error.localizedDescription }
        }
    }

    // MARK: - Save / Finish

    private func saveProgress() {
        UserDefaults.standard.set(chapterIndex, forKey: "chapter_\(book.id)")
        var b = book
        b.readingProgress = overallProgress
        b.lastReadDate    = Date()
        store.updateBook(b)
        book = b
    }

    private func finishBook(notes: String) {
        showCompletion = false
        var b = book
        b.isFinished      = true
        b.finishedDate    = Date()
        b.readingProgress = 1.0
        b.lastReadDate    = Date()
        b.notes           = notes
        UserDefaults.standard.set(max(0, spineURLs.count - 1), forKey: "chapter_\(book.id)")
        store.updateBook(b)
        book = b
        dismiss()
    }

    // MARK: - ZIP helpers

    private func isZIPFile(at url: URL) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: url.path) else { return false }
        let magic = fh.readData(ofLength: 4)
        fh.closeFile()
        return magic.count >= 4 && magic[0] == 0x50 && magic[1] == 0x4B
    }

    private func extractArchive(from source: URL, to dest: URL) throws {
        let archive: Archive
        do {
            archive = try Archive(url: source, accessMode: .read)
        } catch {
            throw NSError(domain: "EPUBReader", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法打开书籍文件（ZIP 格式错误）"])
        }
        let fm = FileManager.default
        for entry in archive {
            guard entry.type != .directory else { continue }
            var path = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            path = path.replacingOccurrences(of: "../", with: "")
            guard !path.isEmpty else { continue }
            let destFile = dest.appendingPathComponent(path)
            try? fm.createDirectory(at: destFile.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            var data = Data()
            _ = try? archive.extract(entry) { data.append($0) }
            if !data.isEmpty { try? data.write(to: destFile) }
        }
    }

    private func cleanupTemp() {
        if let dir = tempDir { try? FileManager.default.removeItem(at: dir) }
    }
}

// MARK: - Completion Sheet

struct BookCompletionSheet: View {
    let bookTitle: String
    let existingNotes: String
    let onComplete: (String) -> Void

    @State private var notes: String = ""
    @Environment(\.dismiss) private var dismiss

    init(bookTitle: String, existingNotes: String, onComplete: @escaping (String) -> Void) {
        self.bookTitle     = bookTitle
        self.existingNotes = existingNotes
        self.onComplete    = onComplete
        _notes = State(initialValue: existingNotes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 52)).foregroundStyle(.accent)
                        Text("读完了！").font(.title2.bold())
                        Text("《\(bookTitle)》")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }.padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("读后感", systemImage: "pencil.line")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                            TextEditor(text: $notes)
                                .scrollContentBackground(.hidden)
                                .background(.clear)
                                .padding(10)
                                .frame(minHeight: 180)
                            if notes.isEmpty {
                                Text("写下你的读后感想…")
                                    .foregroundStyle(Color(.placeholderText))
                                    .padding(16).allowsHitTesting(false)
                            }
                        }.frame(minHeight: 200)
                    }.padding(.horizontal, 20)

                    VStack(spacing: 12) {
                        Button { onComplete(notes) } label: {
                            Text("完成阅读").font(.headline)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.accentColor).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button { dismiss() } label: {
                            Text("稍后再写").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 24)
                }
            }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("跳过") { dismiss() }.font(.subheadline)
                }
            }
        }
    }
}

// MARK: - Settings Panel

struct ReaderSettingsPanel: View {
    @ObservedObject var settings: ReaderSettings
    private let sizes:       [Double] = [14, 16, 18, 20, 22, 24, 26]
    private let lineHeights: [Double] = [1.2, 1.4, 1.6, 1.8, 2.0]
    private let lineLabels:  [Double: String] = [1.2:"紧凑", 1.4:"标准", 1.6:"舒适", 1.8:"宽松", 2.0:"超宽"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Color(.tertiaryLabel)).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Text("阅读设置").font(.headline).frame(maxWidth: .infinity, alignment: .center)

            sectionHeader("字体大小", icon: "textformat.size")
            HStack(spacing: 6) {
                stepBtn(icon: "minus") { step(-1) }.disabled(settings.fontSize <= sizes.first!)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(sizes, id: \.self) { s in
                        Button { settings.fontSize = s } label: {
                            Text("\(Int(s))")
                                .font(.system(size: 11, weight: settings.fontSize == s ? .bold : .regular))
                                .frame(width: 31, height: 31)
                                .background(settings.fontSize == s ? Color.accentColor : Color(.tertiarySystemFill))
                                .foregroundStyle(settings.fontSize == s ? .white : .primary)
                                .clipShape(Circle())
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                stepBtn(icon: "plus") { step(+1) }.disabled(settings.fontSize >= sizes.last!)
            }

            sectionHeader("行间距", icon: "text.alignleft")
            HStack(spacing: 6) {
                ForEach(lineHeights, id: \.self) { h in
                    Button { settings.lineHeight = h } label: {
                        Text(lineLabels[h] ?? "")
                            .font(.system(size: 12, weight: settings.lineHeight == h ? .bold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(settings.lineHeight == h ? Color.accentColor : Color(.tertiarySystemFill))
                            .foregroundStyle(settings.lineHeight == h ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }

            sectionHeader("主题背景", icon: "circle.lefthalf.filled")
            HStack(spacing: 0) {
                ForEach(ReaderTheme.allCases, id: \.self) { t in
                    Button { settings.theme = t } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(Color(hex: t.bg)).frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(
                                        settings.theme == t ? Color.accentColor : Color(.separator),
                                        lineWidth: settings.theme == t ? 2.5 : 1))
                                Text("文").font(.system(size: 13)).foregroundColor(Color(hex: t.fg))
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
                    Button { settings.font = f } label: {
                        Text(f.label)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(settings.font == f ? Color.accentColor : Color(.tertiarySystemFill))
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
        settings.fontSize = sizes[i + d]
    }
}
