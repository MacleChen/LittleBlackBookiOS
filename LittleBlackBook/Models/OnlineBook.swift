import Foundation

struct OnlineBook: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let authors: [String]
    let coverURL: URL?
    let year: Int?
    let source: Source
    let downloadURL: URL?   // EPUB or PDF URL
    let format: String      // "EPUB" or "PDF"

    enum Source: String, Hashable {
        case openLibrary = "Open Library"
        case gutenberg   = "Gutenberg"
        case googleBooks = "全球搜索"
    }

    var authorText: String { authors.joined(separator: ", ") }
    var canDownload: Bool  { downloadURL != nil }
}
