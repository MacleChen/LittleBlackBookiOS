import SwiftUI

/// Routes to the correct reader based on book.format.
struct BookReaderView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @Binding var book: Book

    var body: some View {
        switch book.format {
        case .epub:
            EPUBReaderView(book: $book)
                .environmentObject(store)
        case .txt:
            TXTReaderView(book: $book)
                .environmentObject(store)
        case .pdf:
            PDFReaderView(book: $book)
                .environmentObject(store)
        case .unsupported(let name):
            unsupportedView(name)
        }
    }

    private func unsupportedView(_ name: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            Text("不支持的格式")
                .font(.title2.bold())
            Text("当前版本暂不支持 \(name) 格式")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("返回") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
