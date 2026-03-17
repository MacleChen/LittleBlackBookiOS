import Foundation

actor OnlineBookService {
    static let shared = OnlineBookService()
    private init() {}

    enum Err: LocalizedError {
        case noResults, network(String)
        var errorDescription: String? {
            switch self {
            case .noResults:      return "未找到相关书籍"
            case .network(let m): return "网络错误：\(m)"
            }
        }
    }

    // MARK: - Open Library (Internet Archive)

    /// Searches Open Library broadly (not restricted to ebooks-only).
    /// Books without an IA identifier are still shown but have downloadURL = nil.
    func searchOpenLibrary(query: String, page: Int = 1, limit: Int = 20) async throws -> [OnlineBook] {
        var comps = URLComponents(string: "https://openlibrary.org/search.json")!
        comps.queryItems = [
            .init(name: "q",      value: query),
            .init(name: "fields", value: "key,title,author_name,cover_i,first_publish_year,ia,language"),
            .init(name: "limit",  value: "\(limit)"),
            .init(name: "page",   value: "\(page)")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("LittleBlackBook/1.0 (personal)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Err.network("HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(OLSearchResp.self, from: data)
        let docs = decoded.docs ?? []
        if docs.isEmpty { throw Err.noResults }

        return docs.map { doc in
            let coverURL: URL? = doc.cover_i.flatMap {
                URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg")
            }
            // Build EPUB download URL if an Internet Archive ID exists
            let iaId = doc.ia?.first(where: { !$0.isEmpty })
            let epubURL = iaId.flatMap { URL(string: "https://archive.org/download/\($0)/\($0).epub") }
            return OnlineBook(
                id: doc.key ?? UUID().uuidString,
                title: doc.title ?? "未知书名",
                authors: doc.author_name ?? [],
                coverURL: coverURL,
                year: doc.first_publish_year,
                source: .openLibrary,
                downloadURL: epubURL,
                format: epubURL != nil ? "EPUB" : "-"
            )
        }
    }

    // MARK: - Project Gutenberg (via Gutendex)

    func searchGutenberg(query: String, page: Int = 1) async throws -> [OnlineBook] {
        var comps = URLComponents(string: "https://gutendex.com/books/")!
        comps.queryItems = [
            .init(name: "search",    value: query),
            .init(name: "mime_type", value: "application/epub+zip"),
            .init(name: "page",      value: "\(page)")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("LittleBlackBook/1.0 (personal)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Err.network("HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(GutendexResp.self, from: data)
        let results = decoded.results ?? []
        if results.isEmpty { throw Err.noResults }

        return results.compactMap { book -> OnlineBook? in
            let epubURL = book.formats["application/epub+zip"].flatMap { URL(string: $0) }
            guard epubURL != nil else { return nil }
            let coverURL = book.formats["image/jpeg"].flatMap { URL(string: $0) }
            let authors: [String] = (book.authors ?? []).map { a in
                let parts = a.name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return parts.count == 2 ? "\(parts[1]) \(parts[0])" : a.name
            }
            return OnlineBook(
                id: String(book.id),
                title: book.title ?? "未知书名",
                authors: authors,
                coverURL: coverURL,
                year: book.authors?.first?.birth_year,
                source: .gutenberg,
                downloadURL: epubURL,
                format: "EPUB"
            )
        }
    }

    // MARK: - Google Books API (free, comprehensive, great for Chinese content)

    func searchGoogleBooks(query: String, startIndex: Int = 0) async throws -> [OnlineBook] {
        var comps = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        comps.queryItems = [
            .init(name: "q",          value: query),
            .init(name: "maxResults", value: "20"),
            .init(name: "startIndex", value: "\(startIndex)"),
            .init(name: "orderBy",    value: "relevance"),
            .init(name: "printType",  value: "books")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("LittleBlackBook/1.0 (personal)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Err.network("HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(GBSearchResp.self, from: data)
        let items = decoded.items ?? []
        if items.isEmpty { throw Err.noResults }

        return items.map { item in
            let info = item.volumeInfo
            // Cover URL: upgrade to HTTPS and request larger size
            let coverURL: URL? = (info.imageLinks?.thumbnail ?? info.imageLinks?.smallThumbnail)
                .flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")
                                        .replacingOccurrences(of: "zoom=1", with: "zoom=2")) }

            // Download link: prefer EPUB, fallback PDF
            let epubLink = item.accessInfo?.epub?.downloadLink
            let pdfLink  = item.accessInfo?.pdf?.downloadLink
            let dlURL    = (epubLink ?? pdfLink).flatMap { URL(string: $0) }
            let fmt: String
            if epubLink != nil  { fmt = "EPUB" }
            else if pdfLink != nil { fmt = "PDF" }
            else { fmt = "-" }

            // Parse year from publishedDate (e.g. "2012-01-01" or "2012")
            let year = info.publishedDate.flatMap { Int($0.prefix(4)) }

            return OnlineBook(
                id: item.id,
                title: info.title,
                authors: info.authors ?? [],
                coverURL: coverURL,
                year: year,
                source: .googleBooks,
                downloadURL: dlURL,
                format: fmt
            )
        }
    }

    // MARK: - Download book to temp → returns local URL

    func downloadBook(book: OnlineBook) async throws -> URL {
        guard let downloadURL = book.downloadURL else { throw Err.noResults }
        let (tmpFile, _) = try await URLSession.shared.download(from: downloadURL)
        let ext = book.format.lowercased() == "pdf" ? "pdf" : "epub"
        let safeName = book.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_\(safeName).\(ext)")
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tmpFile, to: destURL)
        return destURL
    }
}

// MARK: - Open Library models

private struct OLSearchResp: Codable {
    let docs: [OLDoc]?
    let numFound: Int?
}
private struct OLDoc: Codable {
    let key: String?
    let title: String?
    let author_name: [String]?
    let cover_i: Int?
    let first_publish_year: Int?
    let ia: [String]?
    let language: [String]?
}

// MARK: - Gutendex models

private struct GutendexResp: Codable {
    let results: [GutBook]?
    let count: Int?
}
private struct GutBook: Codable {
    let id: Int
    let title: String?
    let authors: [GutAuthor]?
    let formats: [String: String]
}
private struct GutAuthor: Codable {
    let name: String
    let birth_year: Int?
    let death_year: Int?
}

// MARK: - Google Books models

private struct GBSearchResp: Codable {
    let items: [GBItem]?
    let totalItems: Int?
}
private struct GBItem: Codable {
    let id: String
    let volumeInfo: GBVolumeInfo
    let accessInfo: GBAccessInfo?
}
private struct GBVolumeInfo: Codable {
    let title: String
    let authors: [String]?
    let publishedDate: String?
    let imageLinks: GBImageLinks?
    let language: String?
}
private struct GBImageLinks: Codable {
    let thumbnail: String?
    let smallThumbnail: String?
}
private struct GBAccessInfo: Codable {
    let epub: GBFormat?
    let pdf: GBFormat?
}
private struct GBFormat: Codable {
    let isAvailable: Bool
    let downloadLink: String?
}
