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

    // MARK: - 豆瓣图书
    // 使用网站自带的 subject_suggest 接口，无需鉴权，稳定性最好

    func searchDouban(query: String, start: Int = 0) async throws -> [OnlineBook] {
        var comps = URLComponents(string: "https://book.douban.com/j/subject_suggest")!
        comps.queryItems = [
            .init(name: "q",    value: query),
            .init(name: "type", value: "b")   // b = book
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("https://book.douban.com", forHTTPHeaderField: "Referer")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/javascript, */*", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 10

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Err.network("豆瓣 HTTP \(http.statusCode)")
        }

        let items = try JSONDecoder().decode([DoubanSuggestItem].self, from: data)
        if items.isEmpty { throw Err.noResults }

        return items.compactMap { item -> OnlineBook? in
            guard let title = item.title, !title.isEmpty else { return nil }

            // Extract numeric ID from url like "/subject/1084336/"
            let id = item.url?
                .components(separatedBy: "/")
                .first(where: { Int($0) != nil }) ?? UUID().uuidString

            // sub_title format: "作者 / 出版社 / 年份"
            let parts = (item.sub_title ?? "")
                .components(separatedBy: "/")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let author = parts.first ?? ""
            let year = parts.compactMap { Int($0.prefix(4)) }.first

            let coverURL = (item.cover_url ?? item.pic)
                .flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) }

            return OnlineBook(
                id: id,
                title: title,
                authors: author.isEmpty ? [] : [author],
                coverURL: coverURL,
                year: year,
                source: .douban,
                downloadURL: nil,
                format: "-"
            )
        }
    }

    // MARK: - Open Library + Archive.org（合并搜索可下载书籍）

    func searchOpenLibrary(query: String, page: Int = 1, limit: Int = 15) async throws -> [OnlineBook] {
        async let olBooks = fetchOpenLibrary(query: query, page: page, limit: limit)
        async let iaBooks = fetchArchiveChinese(query: query, rows: 10)

        var combined: [OnlineBook] = []
        if let ol = try? await olBooks { combined.append(contentsOf: ol) }
        if let ia = try? await iaBooks { combined.append(contentsOf: ia) }

        var seen = Set<String>()
        combined = combined.filter { seen.insert($0.title.prefix(20).lowercased()).inserted }
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

// MARK: - Douban suggest models

private struct DoubanSuggestItem: Codable {
    let type: String?
    let title: String?
    let url: String?
    let cover_url: String?   // some versions use cover_url
    let pic: String?         // some versions use pic
    let sub_title: String?
    let id: String?
    let year: String?
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

// MARK: - Internet Archive models

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
