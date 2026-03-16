import SwiftUI
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator

// ReadiumNavigator also exports a `Color` type; pin this file's Color to SwiftUI.
typealias Color = SwiftUI.Color

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
            fontFamily: readiumFontFamily,
            fontSize:   fontSize / 20.0,   // 20 pt = 1.0 (100 %)
            theme:      readiumTheme
        )
    }

    // Theme is a top-level enum in ReadiumNavigator (not nested in EPUBPreferences)
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

final class EPUBReaderNavigatorDelegate: NSObject, ObservableObject, NavigatorDelegate {
    @Published var currentProgress: Double = 0

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        if let p = locator.locations.totalProgression {
            DispatchQueue.main.async { self.currentProgress = p }
        }
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        print("[Readium] Navigator error:", error)
    }
}

// MARK: - UIViewController host

/// Embeds an existing UIViewController into SwiftUI.
struct NavigatorHostView: UIViewControllerRepresentable {
    let viewController: EPUBNavigatorViewController

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        viewController
    }
    func updateUIViewController(_ vc: EPUBNavigatorViewController, context: Context) {}
}

// MARK: - Main View

struct EPUBReaderView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @Binding var book: Book

    @StateObject private var settings       = ReaderSettings()
    @StateObject private var navDelegate    = EPUBReaderNavigatorDelegate()

    @State private var navigatorVC: EPUBNavigatorViewController?
    @State private var loadError:   String?
    @State private var showControls: Bool = true
    @State private var showSettings: Bool = false

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
            })
            .presentationDetents([.height(310)])
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
            Text("\(Int(navDelegate.currentProgress * 100))%")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
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
        // Readium 3.x: AssetRetriever + PublicationOpener replaces old Streamer API
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

            // 1. Retrieve asset
            let asset = try await assetRetriever.retrieve(url: fileURL).get()

            // 2. Open as Publication
            let publication = try await opener.open(
                asset: asset,
                allowUserInteraction: false
            ).get()

            // 3. Create navigator (no HTTP server needed in Readium 3.x)
            let vc = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: nil,
                config: .init(preferences: settings.readiumPreferences)
            )
            vc.delegate = navDelegate

            await MainActor.run {
                navDelegate.currentProgress = book.readingProgress
                navigatorVC = vc
            }
        } catch {
            await MainActor.run { loadError = error.localizedDescription }
        }
    }

    // ── Save ──────────────────────────────────────────────────────────────────

    private func save() {
        var b = book
        b.readingProgress = navDelegate.currentProgress
        b.lastReadDate    = Date()
        store.updateBook(b)
        book = b
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
