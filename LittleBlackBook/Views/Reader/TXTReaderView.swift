import SwiftUI

struct TXTReaderView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @Binding var book: Book

    @AppStorage("txt_fontSize")   private var fontSize:   Double = 17
    @AppStorage("txt_lineHeight") private var lineHeight: Double = 1.6
    @AppStorage("txt_themeRaw")   private var themeRaw:   String = ReaderTheme.white.rawValue

    @State private var paragraphs:    [String] = []
    @State private var loadError:     String?  = nil
    @State private var showSettings:  Bool = false
    @State private var showControls:  Bool = true
    @State private var scrollTarget:  Int? = nil
    @State private var savedParagraph: Int = 0

    private var theme: ReaderTheme {
        ReaderTheme(rawValue: themeRaw) ?? .white
    }

    var body: some View {
        ZStack {
            theme.uiBG.ignoresSafeArea()

            if let err = loadError {
                errorView(err)
            } else if paragraphs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mainContent
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .task { load() }
        .onDisappear { save() }
        .sheet(isPresented: $showSettings) {
            TXTSettingsPanel(fontSize: $fontSize, lineHeight: $lineHeight, themeRaw: $themeRaw)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            topBar
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: fontSize * lineHeight * 0.5) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { idx, para in
                            Text(para)
                                .font(.system(size: fontSize))
                                .lineSpacing(fontSize * (lineHeight - 1))
                                .foregroundStyle(Color(hex: theme.fg))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                                .onAppear { savedParagraph = idx }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .onTapGesture { showControls.toggle() }
                .task(id: paragraphs.isEmpty ? 0 : 1) {
                    if !paragraphs.isEmpty, let target = scrollTarget {
                        proxy.scrollTo(target, anchor: .top)
                        scrollTarget = nil
                    }
                }
            }

            bottomBar
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
        }
        .animation(.easeInOut(duration: 0.22), value: showControls)
    }

    // MARK: - Bars

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

    private var bottomBar: some View {
        HStack {
            Spacer()
            let total = paragraphs.count
            let pct   = total > 0 ? Int(Double(savedParagraph + 1) / Double(total) * 100) : 0
            Text("\(pct)%")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
            Spacer()
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text(msg).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("返回") { dismiss() }.buttonStyle(.borderedProminent)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load / Save

    private func load() {
        let url = book.fileURL
        // Try UTF-8 → GBK (GB18030) → Big5
        let encodings: [String.Encoding] = [
            .utf8,
            String.Encoding(rawValue: 0x80000632), // GB18030 (superset of GBK/GB2312)
            .utf16,
        ]
        var raw: String?
        for enc in encodings {
            if let s = try? String(contentsOf: url, encoding: enc) { raw = s; break }
        }
        guard let text = raw else {
            loadError = "无法读取文件，请确认文件编码（支持 UTF-8 / GBK）"
            return
        }
        // Split by newlines, collapse blanks, keep chapters intact
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        paragraphs = lines

        // Restore position
        let saved = UserDefaults.standard.integer(forKey: "txt_para_\(book.id)")
        if saved > 0, saved < lines.count {
            scrollTarget = saved
            savedParagraph = saved
        }
    }

    private func save() {
        UserDefaults.standard.set(savedParagraph, forKey: "txt_para_\(book.id)")
        var b = book
        let pct = paragraphs.isEmpty ? 0.0 : Double(savedParagraph + 1) / Double(paragraphs.count)
        b.readingProgress = pct
        b.lastReadDate    = Date()
        store.updateBook(b)
        book = b
    }
}

// MARK: - TXT Settings Panel

private struct TXTSettingsPanel: View {
    @Binding var fontSize:   Double
    @Binding var lineHeight: Double
    @Binding var themeRaw:   String

    private let sizes:       [Double] = [14, 16, 17, 18, 20, 22, 24]
    private let lineHeights: [Double] = [1.2, 1.4, 1.6, 1.8, 2.0]
    private let lhLabels:    [Double: String] = [1.2:"紧凑", 1.4:"标准", 1.6:"舒适", 1.8:"宽松", 2.0:"超宽"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Color(.tertiaryLabel)).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Text("阅读设置").font(.headline).frame(maxWidth: .infinity, alignment: .center)

            sectionHeader("字体大小", icon: "textformat.size")
            HStack(spacing: 4) {
                ForEach(sizes, id: \.self) { s in
                    Button { fontSize = s } label: {
                        Text("\(Int(s))")
                            .font(.system(size: 11, weight: fontSize == s ? .bold : .regular))
                            .frame(maxWidth: .infinity).frame(height: 31)
                            .background(fontSize == s ? Color.accentColor : Color(.tertiarySystemFill))
                            .foregroundStyle(fontSize == s ? .white : .primary)
                            .clipShape(Circle())
                    }.buttonStyle(.plain)
                }
            }

            sectionHeader("行间距", icon: "text.alignleft")
            HStack(spacing: 6) {
                ForEach(lineHeights, id: \.self) { h in
                    Button { lineHeight = h } label: {
                        Text(lhLabels[h] ?? "\(h)")
                            .font(.system(size: 12, weight: lineHeight == h ? .bold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(lineHeight == h ? Color.accentColor : Color(.tertiarySystemFill))
                            .foregroundStyle(lineHeight == h ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }

            sectionHeader("主题背景", icon: "circle.lefthalf.filled")
            HStack(spacing: 0) {
                ForEach(ReaderTheme.allCases, id: \.self) { t in
                    Button { themeRaw = t.rawValue } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(Color(hex: t.bg)).frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(
                                        themeRaw == t.rawValue ? Color.accentColor : Color(.separator),
                                        lineWidth: themeRaw == t.rawValue ? 2.5 : 1))
                                Text("文").font(.system(size: 13))
                                    .foregroundColor(Color(hex: t.fg))
                            }
                            Text(t.label).font(.system(size: 10))
                                .foregroundStyle(themeRaw == t.rawValue ? Color.accentColor : .secondary)
                        }
                    }.buttonStyle(.plain).frame(maxWidth: .infinity)
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
}
