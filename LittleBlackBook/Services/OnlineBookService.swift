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
            .init(name: "fields", value: "key,title,author_name,cover_i,first_publish_year,ia,has_fulltext"),
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
            // Use the first IA identifier; prefer the standard EPUB URL
            let iaId = doc.ia?.first(where: { !$0.isEmpty })
            let epubURL = iaId.flatMap {
                URL(string: "https://archive.org/download/\($0)/\($0).epub")
            }
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
            // Prefer the direct cache URL — avoids Gutenberg's redirect that often 403s
            let cacheURL = URL(string: "https://www.gutenberg.org/cache/epub/\(book.id)/pg\(book.id).epub")
            let fallbackURL = book.formats["application/epub+zip"].flatMap { URL(string: $0) }
            let epubURL = cacheURL ?? fallbackURL
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

        let (tmpFile, response) = try await performDownload(url: downloadURL)

        // Handle HTTP errors with source-specific retry and messages
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tmpFile)

            if http.statusCode == 403 {
                // Gutenberg: try the -images / non-images variant
                if book.source == .gutenberg, let altURL = gutenbergAlternativeURL(downloadURL) {
                    if let result = try? await retryDownload(url: altURL, book: book) { return result }
                }
                // Archive.org: try _epub.epub suffix variant
                if book.source == .openLibrary {
                    let s = downloadURL.absoluteString
                    if let altURL = URL(string: s.hasSuffix(".epub")
                                        ? String(s.dropLast(5)) + "_epub.epub" : s) {
                        if let result = try? await retryDownload(url: altURL, book: book) { return result }
                    }
                }
            }

            throw Err.network(errorMessage(for: http.statusCode, source: book.source))
        }

        return try finalize(tmpFile: tmpFile, book: book)
    }

    // MARK: - Download helpers

    private func performDownload(url: URL) async throws -> (URL, URLResponse) {
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        req.setValue("application/epub+zip, application/pdf, */*;q=0.8",
                     forHTTPHeaderField: "Accept")
        req.timeoutInterval = 90
        return try await URLSession.shared.download(for: req)
    }

    private func retryDownload(url: URL, book: OnlineBook) async throws -> URL {
        let (file, resp) = try await performDownload(url: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: file)
            throw Err.noResults
        }
        return try finalize(tmpFile: file, book: book)
    }

    /// For a Gutenberg cache URL pg{id}.epub, try pg{id}-images.epub (and vice-versa).
    private func gutenbergAlternativeURL(_ url: URL) -> URL? {
        let s = url.absoluteString
        if s.hasSuffix(".epub") && !s.hasSuffix("-images.epub") {
            return URL(string: s.dropLast(5) + "-images.epub")
        }
        if s.hasSuffix("-images.epub") {
            return URL(string: String(s.dropLast("-images.epub".count)) + ".epub")
        }
        return nil
    }

    private func errorMessage(for status: Int, source: OnlineBook.Source) -> String {
        switch status {
        case 403:
            switch source {
            case .gutenberg:
                return "Gutenberg 拒绝访问（403）。该书可能有版权限制，请前往 gutenberg.org 手动下载"
            case .openLibrary:
                return "该书需要登录 Internet Archive 账号才能借阅下载（403）"
            case .douban:
                return "豆瓣图书不提供直接下载（403）"
            }
        case 404:
            return "下载链接已失效（404），该书籍文件已不存在"
        default:
            return "服务器返回 \(status)，下载失败"
        }
    }

    private func finalize(tmpFile: URL, book: OnlineBook) throws -> URL {
        let ext = book.format.lowercased() == "pdf" ? "pdf" : "epub"

        // Validate magic bytes
        if let fh = FileHandle(forReadingAtPath: tmpFile.path) {
            let magic = fh.readData(ofLength: 4)
            fh.closeFile()
            let isEPUB = magic.count >= 4 && magic[0] == 0x50 && magic[1] == 0x4B
            let isPDF  = magic.count >= 4 && magic[0] == 0x25 && magic[1] == 0x50
            guard isEPUB || isPDF else {
                try? FileManager.default.removeItem(at: tmpFile)
                throw Err.network("下载内容不是有效的 EPUB/PDF 文件（可能是版权限制或链接失效）")
            }
        }

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
