import SwiftUI
import WebKit
import ZIPFoundation

// MARK: - Settings

class ReaderSettings: ObservableObject {
    @AppStorage("r_fontSize")   var fontSize:   Double = 20
    @AppStorage("r_lineHeight") var lineHeight: Double = 1.5
    @AppStorage("r_theme")      var themeRaw:   String = ReaderTheme.white.rawValue
    @AppStorage("r_font")       var fontRaw:    String = ReaderFont.system.rawValue
    var theme: ReaderTheme { get { .init(rawValue: themeRaw) ?? .white } set { themeRaw = newValue.rawValue } }
    var font:  ReaderFont  { get { .init(rawValue: fontRaw)  ?? .system } set { fontRaw  = newValue.rawValue } }

    var css: String {
        let family: String
        switch font {
        case .system:  family = "-apple-system, 'PingFang SC', sans-serif"
        case .serif:   family = "Georgia, 'Songti SC', 'SimSun', serif"
        case .rounded: family = "-apple-system, 'PingFang SC', sans-serif"
        }
        return """
        html, body {
          background-color: \(theme.bg) !important;
          font-family: \(family) !important;
          max-width: 700px;
          margin: 0 auto;
          padding: 20px 16px 60px;
        }
        body, body * {
          font-size: \(fontSize)px !important;
          line-height: \(lineHeight) !important;
          color: \(theme.fg) !important;
          background-color: \(theme.bg) !important;
        }
        * { box-sizing: border-box; }
        img, img * { max-width: 100% !important; height: auto !important;
                     display: block; margin: 0 auto;
                     background-color: transparent !important; }
        a, a * { color: \(theme.fg) !important; }
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

// MARK: - Chapter ViewController (one per chapter page)

final class ChapterVC: UIViewController, WKNavigationDelegate {
    var index: Int = 0
    private(set) var webView: WKWebView!
    private var chapterURL: URL?
    private var rootDir: URL?
    private var pendingCSS: String = ""
    var onTap: (() -> Void)?
    var bgColor: UIColor = .white

    func configure(url: URL, rootDir: URL, css: String,
                   bgColor: UIColor, onTap: @escaping () -> Void) {
        self.chapterURL = url
        self.rootDir    = rootDir
        self.pendingCSS = css
        self.bgColor    = bgColor
        self.onTap      = onTap
        if isViewLoaded {
            applyBackground()
            loadContent()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyBackground()

        let wv = WKWebView(frame: view.bounds)
        wv.autoresizingMask  = [.flexibleWidth, .flexibleHeight]
        wv.navigationDelegate = self
        wv.isOpaque = false
        wv.scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(wv)
        self.webView = wv

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        tap.cancelsTouchesInView = false
        wv.addGestureRecognizer(tap)

        loadContent()
    }

    private func applyBackground() {
        view.backgroundColor = bgColor
        webView?.backgroundColor = bgColor
        webView?.scrollView.backgroundColor = bgColor
    }

    private func loadContent() {
        guard let url = chapterURL, let root = rootDir else { return }
        webView.loadFileURL(url, allowingReadAccessTo: root)
    }

    func applyCSS(_ css: String, bgColor: UIColor? = nil) {
        pendingCSS = css
        if let bg = bgColor {
            self.bgColor = bg
            if isViewLoaded { applyBackground() }
        }
        guard isViewLoaded else { return }
        injectCSS()
    }

    private func injectCSS() {
        let escaped = pendingCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'",  with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = """
        (function(){
          var e=document.getElementById('_rs'); if(e) e.remove();
          var s=document.createElement('style'); s.id='_rs';
          s.textContent='\(escaped)';
          (document.head||document.documentElement).appendChild(s);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectCSS()
    }

    @objc private func didTap() { onTap?() }
}

// MARK: - UIPageViewController wrapper

struct PagedEPUBReader: UIViewControllerRepresentable {
    @Binding var chapterIndex: Int
    let spineURLs:  [URL]
    let rootDir:    URL
    let css:        String
    let bgColor:    UIColor
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .scroll,
                                       navigationOrientation: .horizontal)
        pvc.view.backgroundColor = bgColor
        pvc.dataSource = context.coordinator
        pvc.delegate   = context.coordinator
        let vc = context.coordinator.chapterVC(for: chapterIndex)
        pvc.setViewControllers([vc], direction: .forward, animated: false)
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        pvc.view.backgroundColor = bgColor
        // Push updated CSS + bgColor to all cached VCs
        context.coordinator.applyCSS(css, bgColor: bgColor)
        // External navigation (bottom bar buttons) — sync UIPageViewController
        guard let current = pvc.viewControllers?.first as? ChapterVC,
              current.index != chapterIndex else { return }
        let dir: UIPageViewController.NavigationDirection =
            chapterIndex > current.index ? .forward : .reverse
        let vc = context.coordinator.chapterVC(for: chapterIndex)
        pvc.setViewControllers([vc], direction: dir, animated: true)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject,
                              UIPageViewControllerDataSource,
                              UIPageViewControllerDelegate {
        var parent: PagedEPUBReader
        private var cache: [Int: ChapterVC] = [:]

        init(_ parent: PagedEPUBReader) { self.parent = parent }

        func chapterVC(for index: Int) -> ChapterVC {
            if let cached = cache[index] { return cached }
            let vc = ChapterVC()
            vc.index = index
            vc.configure(url: parent.spineURLs[index],
                         rootDir: parent.rootDir,
                         css: parent.css,
                         bgColor: parent.bgColor,
                         onTap: parent.onTap)
            cache[index] = vc
            // Keep cache small (max 5 chapters around current)
            evictDistant(from: index)
            return vc
        }

        func applyCSS(_ css: String, bgColor: UIColor) {
            cache.values.forEach { $0.applyCSS(css, bgColor: bgColor) }
        }

        private func evictDistant(from center: Int) {
            let keep = Set((center - 2)...(center + 2))
            cache.keys.filter { !keep.contains($0) }.forEach { cache.removeValue(forKey: $0) }
        }

        // DataSource
        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let c = vc as? ChapterVC, c.index > 0 else { return nil }
            return chapterVC(for: c.index - 1)
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let c = vc as? ChapterVC,
                  c.index < parent.spineURLs.count - 1 else { return nil }
            return chapterVC(for: c.index + 1)
        }

        // Delegate — update binding after swipe completes
        func pageViewController(_ pvc: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed,
                  let vc = pvc.viewControllers?.first as? ChapterVC else { return }
            DispatchQueue.main.async { self.parent.chapterIndex = vc.index }
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

                    PagedEPUBReader(
                        chapterIndex: $chapterIndex,
                        spineURLs: spineURLs,
                        rootDir: dir,
                        css: settings.css,
                        bgColor: UIColor(settings.theme.uiBG),
                        onTap: { showControls.toggle() }
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

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button {
                guard chapterIndex > 0 else { return }
                chapterIndex -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14))
                    .frame(width: 44, height: 36)
            }
            .disabled(chapterIndex == 0)

            Spacer()

            if totalChapters > 0 {
                Text("第 \(chapterIndex + 1) / \(totalChapters) 章")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }

            Spacer()

            Button {
                if chapterIndex < totalChapters - 1 {
                    chapterIndex += 1
                } else {
                    showCompletion = true
                }
            } label: {
                Image(systemName: chapterIndex < totalChapters - 1 ? "chevron.right" : "checkmark.circle")
                    .font(.system(size: 14))
                    .frame(width: 44, height: 36)
            }
        }
        .padding(.horizontal, 16)
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

    // MARK: - Load

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
        guard let archive = Archive(url: source, accessMode: .read) else {
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
                            .font(.system(size: 52))
                            .foregroundStyle(.accent)
                        Text("读完了！").font(.title2.bold())
                        Text("《\(bookTitle)》")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

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
                        }
                        .frame(minHeight: 200)
                    }
                    .padding(.horizontal, 20)

                    VStack(spacing: 12) {
                        Button { onComplete(notes) } label: {
                            Text("完成阅读")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button { dismiss() } label: {
                            Text("稍后再写").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
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
    private let lineHeights: [Double] = [1.0, 1.2, 1.5, 1.8, 2.0]
    private let lineHeightLabels: [Double: String] = [1.0:"紧凑", 1.2:"标准", 1.5:"舒适", 1.8:"宽松", 2.0:"超宽"]

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
                        Text(lineHeightLabels[h] ?? "\(h)")
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
