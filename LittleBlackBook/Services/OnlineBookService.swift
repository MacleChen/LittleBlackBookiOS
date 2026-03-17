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

    // MARK: - 豆瓣图书（覆盖中文书籍，含当代小说）

    func searchDouban(query: String, start: Int = 0) async throws -> [OnlineBook] {
        var comps = URLComponents(string: "https://book.douban.com/j/search_subjects")!
        comps.queryItems = [
            .init(name: "type",       value: "book"),
            .init(name: "query",      value: query),
            .init(name: "sort",       value: "rank"),
            .init(name: "page_limit", value: "20"),
            .init(name: "page_start", value: "\(start)")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("https://book.douban.com",  forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Err.network("豆瓣 HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(DoubanResp.self, from: data)
        let subjects = decoded.subjects ?? []
        if subjects.isEmpty { throw Err.noResults }

        return subjects.map { s in
            // abstract 通常格式: "作者 / 出版社 / 年份" 或 "作者 / 年份"
            let parts = s.abstract?.components(separatedBy: " / ").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            let author = parts.first ?? "未知作者"
            let yearStr = parts.first(where: { $0.count >= 4 && Int($0.prefix(4)) != nil })
            let year = yearStr.flatMap { Int($0.prefix(4)) }

            let coverURL = s.cover.flatMap {
                // Upgrade to HTTPS and use large cover
                URL(string: $0.replacingOccurrences(of: "http://", with: "https://")
                               .replacingOccurrences(of: "/m/", with: "/l/")
                               .replacingOccurrences(of: "/s/", with: "/l/"))
            }

            return OnlineBook(
                id: s.id ?? UUID().uuidString,
                title: s.title ?? "未知书名",
                authors: author.isEmpty ? [] : [author],
                coverURL: coverURL,
                year: year,
                source: .douban,
                downloadURL: nil,   // 豆瓣仅提供元数据，版权书无免费下载
                format: "-"
            )
        }
    }

    // MARK: - Open Library + Archive.org（合并搜索可下载书籍）

    /// Searches Open Library and Internet Archive Chinese texts in parallel,
    /// returns combined results sorted so downloadable books come first.
    func searchOpenLibrary(query: String, page: Int = 1, limit: Int = 15) async throws -> [OnlineBook] {
        async let olBooks   = fetchOpenLibrary(query: query, page: page, limit: limit)
        async let iaBooks   = fetchArchiveChinese(query: query, rows: 10)

        var combined: [OnlineBook] = []
        if let ol = try? await olBooks  { combined.append(contentsOf: ol) }
        if let ia = try? await iaBooks  { combined.append(contentsOf: ia) }

        // Deduplicate by title prefix
        var seen = Set<String>()
        combined = combined.filter { seen.insert($0.title.prefix(20).lowercased()).inserted }

        // Downloadable first
        combined.sort { $0.canDownload && !$1.canDownload }

        if combined.isEmpty { throw Err.noResults }
        return combined
    }

    private func fetchOpenLibrary(query: String, page: Int, limit: Int) async throws -> [OnlineBook] {
        var comps = URLComponents(string: "https://openlibrary.org/search.json")!
        comps.queryItems = [
            .init(name: "q",      value: query),
            .init(name: "fields", value: "key,title,author_name,cover_i,first_publish_year,ia"),
            .init(name: "limit",  value: "\(limit)"),
            .init(name: "page",   value: "\(page)")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("LittleBlackBook/1.0 (personal)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw Err.noResults
        }

        let decoded = try JSONDecoder().decode(OLSearchResp.self, from: data)
        return (decoded.docs ?? []).map { doc in
            let coverURL = doc.cover_i.flatMap {
                URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg")
            }
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

    /// Search Internet Archive directly for Chinese-language texts.
    private func fetchArchiveChinese(query: String, rows: Int) async throws -> [OnlineBook] {
        var comps = URLComponents(string: "https://archive.org/advancedsearch.php")!
        comps.queryItems = [
            .init(name: "q",       value: "title:(\(query)) AND language:(Chinese) AND mediatype:(texts)"),
            .init(name: "fl[]",    value: "identifier,title,creator,year"),
            .init(name: "sort[]",  value: "downloads desc"),
            .init(name: "rows",    value: "\(rows)"),
            .init(name: "output",  value: "json")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("LittleBlackBook/1.0 (personal)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        let decoded = try JSONDecoder().decode(IASearchResp.self, from: data)
        return (decoded.response?.docs ?? []).compactMap { doc in
            guard let identifier = doc.identifier, !identifier.isEmpty else { return nil }
            let epubURL = URL(string: "https://archive.org/download/\(identifier)/\(identifier).epub")
            return OnlineBook(
                id: identifier,
                title: doc.title ?? identifier,
                authors: doc.creator.map { [$0] } ?? [],
                coverURL: URL(string: "https://archive.org/services/img/\(identifier)"),
                year: doc.year.flatMap { Int($0) },
                source: .openLibrary,
                downloadURL: epubURL,
                format: "EPUB"
            )
        }
    }

    // MARK: - Project Gutenberg

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
            throw Err.network("Gutenberg HTTP \(http.statusCode)")
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

    // MARK: - Download

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

// MARK: - Douban models

private struct DoubanResp: Codable {
    let subjects: [DoubanSubject]?
}
private struct DoubanSubject: Codable {
    let id: String?
    let title: String?
    let cover: String?
    let abstract: String?
    let url: String?
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
}

// MARK: - Internet Archive Advanced Search models

private struct IASearchResp: Codable {
    let response: IAResponse?
}
private struct IAResponse: Codable {
    let numFound: Int?
    let docs: [IADoc]?
}
private struct IADoc: Codable {
    let identifier: String?
    let title: String?
    let creator: String?
    let year: String?
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
