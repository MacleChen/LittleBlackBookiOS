import SwiftUI
import PDFKit

struct PDFReaderView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @Binding var book: Book

    @State private var showControls = true

    var body: some View {
        ZStack(alignment: .top) {
            PDFKitView(url: book.fileURL) { page, total in
                saveProgress(page: page, total: total)
            }
            .ignoresSafeArea()
            .onTapGesture { showControls.toggle() }

            if showControls {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showControls)
        .onDisappear { saveBook() }
    }

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
            // placeholder to balance layout
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func saveProgress(page: Int, total: Int) {
        guard total > 0 else { return }
        let pct = Double(page) / Double(total)
        var b = book
        b.readingProgress = pct
        b.lastReadDate = Date()
        store.updateBook(b)
        book = b
    }

    private func saveBook() {
        var b = book
        b.lastReadDate = Date()
        store.updateBook(b)
        book = b
    }
}

// MARK: - UIViewRepresentable

struct PDFKitView: UIViewRepresentable {
    let url: URL
    let onPageChanged: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}

    class Coordinator: NSObject {
        let onPageChanged: (Int, Int) -> Void
        weak var pdfView: PDFView?

        init(onPageChanged: @escaping (Int, Int) -> Void) {
            self.onPageChanged = onPageChanged
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView,
                  let document = pdfView.document,
                  let currentPage = pdfView.currentPage else { return }
            let idx   = document.index(for: currentPage)
            let total = document.pageCount
            onPageChanged(idx + 1, total)
        }
    }
}
