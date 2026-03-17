import SwiftUI
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator

// ReadiumNavigator also exports a `Color` type; pin this file's Color to SwiftUI.
typealias Color = SwiftUI.Color

// MARK: - Settings

class ReaderSettings: ObservableObject {
    @AppStorage("r_fontSize")   var fontSize:   Double = 20
    @AppStorage("r_lineHeight") var lineHeight: Double = 1.5
    @AppStorage("r_theme")      var themeRaw:   String = ReaderTheme.white.rawValue
    @AppStorage("r_font")       var fontRaw:    String = ReaderFont.system.rawValue
    var theme: ReaderTheme { get { .init(rawValue: themeRaw) ?? .white } set { themeRaw = newValue.rawValue } }
    var font:  ReaderFont  { get { .init(rawValue: fontRaw)  ?? .system } set { fontRaw  = newValue.rawValue } }
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

// MARK: - Settings → Readium Preferences bridge

extension ReaderSettings {
    var readiumPreferences: EPUBPreferences {
        EPUBPreferences(
            fontFamily:     readiumFontFamily,
            fontSize:       fontSize / 20.0,   // 20 pt = 1.0 (100 %)
            lineHeight:     lineHeight,
            publisherStyles: false,            // required for lineHeight / font overrides to apply
            theme:          readiumTheme
        )
    }

    private var readiumTheme: Theme {
        switch theme {
        case .white:        return .light
        case .sepia:        return .sepia
        case .dark, .night: return .dark
        }
    }

    private var readiumFontFamily: FontFamily? {
        switch font {
        case .system:  return nil
        case .serif:   return FontFamily(rawValue: "Georgia")
        case .rounded: return nil
        }
    }
}

// MARK: - Navigator Delegate

@MainActor
final class EPUBReaderNavigatorDelegate: NSObject, ObservableObject, EPUBNavigatorDelegate {
    @Published var currentProgress: Double = 0
    @Published var currentLocator: Locator?
    @Published var currentPosition: Int = 0
    @Published var totalPositions: Int = 0
    @Published var isOnLastPage: Bool = false

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        currentLocator = locator
        if let p = locator.locations.totalProgression { currentProgress = p }
        if let pos = locator.locations.position {
            currentPosition = pos
            isOnLastPage = totalPositions > 0 && pos >= totalPositions
        }
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        print("[Readium] Navigator error:", error)
    }
}

// MARK: - UIViewController host

struct NavigatorHostView: UIViewControllerRepresentable {
    let viewController: EPUBNavigatorViewController

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { viewController }
    func updateUIViewController(_ vc: EPUBNavigatorViewController, context: Context) {}
}

// MARK: - Main View

struct EPUBReaderView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @Binding var book: Book

    @StateObject private var settings    = ReaderSettings()
    @StateObject private var navDelegate = EPUBReaderNavigatorDelegate()

    @State private var navigatorVC:       EPUBNavigatorViewController?
    @State private var openedPublication: Publication?
    @State private var loadError:         String?
    @State private var showControls:      Bool = true
    @State private var showSettings:      Bool = false
    @State private var showCompletion:    Bool = false

    var body: some View {
        ZStack {
            settings.theme.uiBG.ignoresSafeArea()

            if let error = loadError {
                errorView(error)
            } else if let vc = navigatorVC {
                VStack(spacing: 0) {
                    topBar
                        .opacity(showControls ? 1 : 0)
                        .allowsHitTesting(showControls)

                    NavigatorHostView(viewController: vc)
                        .onTapGesture { showControls.toggle() }
                        // Detect forward-swipe on last page to trigger completion
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 40)
                                .onEnded { value in
                                    guard navDelegate.isOnLastPage else { return }
                                    if value.translation.width < -40 {
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
        .onDisappear { save() }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel(settings: settings, onChanged: {
                navigatorVC?.submitPreferences(settings.readiumPreferences)
                Task { await recomputePositions() }
            })
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

    // ── Bottom bar ────────────────────────────────────────────────────────────

    private var bottomBar: some View {
        HStack {
            Spacer()
            if navDelegate.totalPositions > 0 {
                Text("\(navDelegate.currentPosition) / \(navDelegate.totalPositions)")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
            } else {
                Text("\(Int(navDelegate.currentProgress * 100))%")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // ── Utility ───────────────────────────────────────────────────────────────

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

    // ── Load ──────────────────────────────────────────────────────────────────

    private func loadBook() async {
        let httpClient     = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )

        do {
            guard let fileURL = FileURL(url: book.fileURL) else {
                await MainActor.run { loadError = "无法解析文件路径" }
                return
            }

            let asset = try await assetRetriever.retrieve(url: fileURL).get()
            let publication = try await opener.open(
                asset: asset,
                allowUserInteraction: false
            ).get()

            let total: Int
            if let positions = try? await publication.positionsByReadingOrder().get() {
                total = positions.flatMap { $0 }.count
            } else {
                total = 0
            }

            let savedLocator: Locator? = {
                guard let json = UserDefaults.standard.string(forKey: "locator_\(book.id)") else { return nil }
                return try? Locator(jsonString: json)
            }()

            let vc = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: savedLocator,
                config: .init(preferences: settings.readiumPreferences)
            )
            vc.delegate = navDelegate

            await MainActor.run {
                openedPublication           = publication
                navDelegate.totalPositions  = total
                navDelegate.currentProgress = book.readingProgress
                navigatorVC = vc
            }
        } catch {
            await MainActor.run { loadError = error.localizedDescription }
        }
    }

    // ── Recompute positions after preference change ────────────────────────────

    private func recomputePositions() async {
        guard let pub = openedPublication else { return }
        if let positions = try? await pub.positionsByReadingOrder().get() {
            let total = positions.flatMap { $0 }.count
            await MainActor.run { navDelegate.totalPositions = total }
        }
    }

    // ── Finish book (called from completion sheet) ─────────────────────────────

    private func finishBook(notes: String) {
        showCompletion = false
        var b = book
        b.isFinished      = true
        b.finishedDate    = Date()
        b.readingProgress = 1.0
        b.lastReadDate    = Date()
        b.notes           = notes
        if let locator = navDelegate.currentLocator, let json = locator.jsonString {
            UserDefaults.standard.set(json, forKey: "locator_\(book.id)")
        }
        store.updateBook(b)
        book = b
        dismiss()
    }

    // ── Save on disappear ─────────────────────────────────────────────────────

    private func save() {
        if let locator = navDelegate.currentLocator, let json = locator.jsonString {
            UserDefaults.standard.set(json, forKey: "locator_\(book.id)")
        }
        var b = book
        b.readingProgress = navDelegate.currentProgress
        b.lastReadDate    = Date()
        store.updateBook(b)
        book = b
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
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.accent)
                        Text("读完了！")
                            .font(.title2.bold())
                        Text("《\(bookTitle)》")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    // Notes editor
                    VStack(alignment: .leading, spacing: 8) {
                        Label("读后感", systemImage: "pencil.line")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

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
                                    .padding(16)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(minHeight: 200)
                    }
                    .padding(.horizontal, 20)

                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            onComplete(notes)
                        } label: {
                            Text("完成阅读")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            dismiss()
                        } label: {
                            Text("稍后再写")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("跳过") { dismiss() }
                        .font(.subheadline)
                }
            }
        }
    }
}

// MARK: - Settings Panel

struct ReaderSettingsPanel: View {
    @ObservedObject var settings: ReaderSettings
    var onChanged: (() -> Void)? = nil
    private let sizes:       [Double] = [14, 16, 18, 20, 22, 24, 26]
    private let lineHeights: [Double] = [1.0, 1.2, 1.5, 1.8, 2.0]
    private let lineHeightLabels: [Double: String] = [1.0:"紧凑", 1.2:"标准", 1.5:"舒适", 1.8:"宽松", 2.0:"超宽"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Color(.tertiaryLabel)).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Text("阅读设置").font(.headline).frame(maxWidth: .infinity, alignment: .center)

            // ── Font size ──
            sectionHeader("字体大小", icon: "textformat.size")
            HStack(spacing: 6) {
                stepBtn(icon: "minus") { step(-1) }.disabled(settings.fontSize <= sizes.first!)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(sizes, id: \.self) { s in
                        Button { settings.fontSize = s; onChanged?() } label: {
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

            // ── Line height ──
            sectionHeader("行间距", icon: "text.alignleft")
            HStack(spacing: 6) {
                ForEach(lineHeights, id: \.self) { h in
                    Button { settings.lineHeight = h; onChanged?() } label: {
                        Text(lineHeightLabels[h] ?? "\(h)")
                            .font(.system(size: 12, weight: settings.lineHeight == h ? .bold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(settings.lineHeight == h ? Color.accentColor : Color(.tertiarySystemFill))
                            .foregroundStyle(settings.lineHeight == h ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }

            // ── Theme ──
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

            // ── Font ──
            sectionHeader("字体", icon: "character")
            HStack(spacing: 8) {
                ForEach(ReaderFont.allCases, id: \.self) { f in
                    Button { settings.font = f; onChanged?() } label: {
                        Text(f.label).font(.system(size: 13, weight: .medium))
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
        settings.fontSize = sizes[i + d]; onChanged?()
    }
}
