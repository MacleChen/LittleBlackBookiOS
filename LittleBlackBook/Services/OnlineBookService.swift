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
            // Use the API URL as-is; actual multi-URL retry happens at download time
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

    // MARK: - Standard Ebooks (OPDS)

    func searchStandardEbooks(query: String) async throws -> [OnlineBook] {
        var comps = URLComponents(string: "https://standardebooks.org/feeds/opds/search")!
        comps.queryItems = [.init(name: "q", value: query)]
        var req = URLRequest(url: comps.url!)
        req.setValue("LittleBlackBook/1.0 (personal)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/atom+xml, application/xml, */*;q=0.8", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Err.network("Standard Ebooks HTTP \(http.statusCode)")
        }

        let parser = OPDSAtomParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()

        if parser.books.isEmpty { throw Err.noResults }
        return parser.books
    }

    // MARK: - Download

    func downloadBook(book: OnlineBook) async throws -> URL {
        guard let downloadURL = book.downloadURL else { throw Err.noResults }

        switch book.source {
        case .gutenberg:
            return try await downloadGutenberg(book: book, apiURL: downloadURL)
        case .openLibrary:
            return try await downloadArchiveOrg(book: book, hintURL: downloadURL)
        case .standardEbooks:
            return try await downloadStandardEbooks(url: downloadURL, book: book)
        case .douban:
            throw Err.network("豆瓣图书不提供直接下载，请手动导入 EPUB 文件")
        }
    }

    private func downloadStandardEbooks(url: URL, book: OnlineBook) async throws -> URL {
        let (tmp, resp) = try await performDownload(url: url, referer: "https://standardebooks.org/")
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tmp)
            throw Err.network("Standard Ebooks 下载失败，服务器返回 \(http.statusCode)")
        }
        return try finalize(tmpFile: tmp, book: book)
    }

    // MARK: - Source-specific download strategies

    /// Gutenberg: try cache URLs in order (images → no-images → original API URL).
    private func downloadGutenberg(book: OnlineBook, apiURL: URL) async throws -> URL {
        // Extract numeric book ID from book.id ("1342") or from the API URL path
        let gutenbergId: Int? = Int(book.id) ?? {
            // URL looks like https://www.gutenberg.org/ebooks/1342.epub.images
            let parts = apiURL.deletingPathExtension().lastPathComponent
            return Int(parts.replacingOccurrences(of: ".epub", with: ""))
        }()

        var candidates: [URL] = []
        if let gid = gutenbergId {
            let wwwBase  = "https://www.gutenberg.org/cache/epub/\(gid)/pg\(gid)"
            let pglafBase = "https://gutenberg.pglaf.org/cache/epub/\(gid)/pg\(gid)"
            candidates.append(contentsOf: [
                URL(string: "\(pglafBase)-images.epub")!,  // PGLAF mirror (no Cloudflare)
                URL(string: "\(pglafBase).epub")!,
                URL(string: "\(wwwBase)-images.epub")!,
                URL(string: "\(wwwBase).epub")!,
                URL(string: "\(wwwBase)-h.epub")!,
            ])
        }
        candidates.append(apiURL)   // original Gutendex URL (redirect) as last resort

        var lastError: Error = Err.noResults
        for url in candidates {
            do {
                let (tmp, resp) = try await performDownload(url: url,
                                                            referer: "https://www.gutenberg.org/")
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return try finalize(tmpFile: tmp, book: book)
                }
                try? FileManager.default.removeItem(at: tmp)
                if let http = resp as? HTTPURLResponse, http.statusCode == 403 { continue }
                if let http = resp as? HTTPURLResponse, http.statusCode == 404 { continue }
            } catch {
                lastError = error
            }
        }
        throw Err.network("Gutenberg 所有下载地址均失败，请前往 gutenberg.org 手动下载（\(lastError.localizedDescription)）")
    }

    /// Archive.org / Open Library: query the IA metadata API for the actual EPUB filename,
    /// then download that exact file.
    private func downloadArchiveOrg(book: OnlineBook, hintURL: URL) async throws -> URL {
        // Extract IA identifier from URL: https://archive.org/download/{identifier}/...
        let pathParts = hintURL.pathComponents   // ["", "download", "{id}", "{file}"]
        guard pathParts.count >= 3, pathParts[1] == "download" else {
            // Not an IA URL — try direct download
            return try await directDownload(url: hintURL, book: book)
        }
        let identifier = pathParts[2]

        // Fetch IA metadata to get real file list
        let metaURL = URL(string: "https://archive.org/metadata/\(identifier)")!
        var metaReq = URLRequest(url: metaURL)
        metaReq.setValue("LittleBlackBook/1.0", forHTTPHeaderField: "User-Agent")
        metaReq.timeoutInterval = 15

        if let (metaData, _) = try? await URLSession.shared.data(for: metaReq),
           let meta = try? JSONDecoder().decode(IAMetadataResp.self, from: metaData) {

            // Prefer original-source epub; fall back to any epub
            let epubFiles = (meta.files ?? []).filter {
                $0.name.lowercased().hasSuffix(".epub")
            }
            let preferred = epubFiles.first(where: { $0.source == "original" })
                         ?? epubFiles.first

            if let name = preferred?.name {
                let epubURL = URL(string: "https://archive.org/download/\(identifier)/\(name)")!
                return try await directDownload(url: epubURL, book: book)
            }

            // No epub found in metadata
            throw Err.network("此书在 Internet Archive 上没有 EPUB 文件（可能仅支持在线借阅）")
        }

        // Metadata fetch failed — fall back to hintURL
        return try await directDownload(url: hintURL, book: book)
    }

    private func directDownload(url: URL, book: OnlineBook) async throws -> URL {
        let (tmp, resp) = try await performDownload(url: url,
                                                    referer: "https://archive.org/")
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tmp)
            let msg: String
            switch http.statusCode {
            case 403: msg = "此书需要登录 Internet Archive 账号才能借阅下载（403）"
            case 404: msg = "文件不存在（404），该书可能已被移除"
            default:  msg = "服务器返回 \(http.statusCode)，下载失败"
            }
            throw Err.network(msg)
        }
        return try finalize(tmpFile: tmp, book: book)
    }

    // MARK: - Shared helpers

    private func performDownload(url: URL, referer: String? = nil) async throws -> (URL, URLResponse) {
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        req.setValue("application/epub+zip, application/pdf, */*;q=0.8",
                     forHTTPHeaderField: "Accept")
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        req.timeoutInterval = 90
        return try await URLSession.shared.download(for: req)
    }

    private func finalize(tmpFile: URL, book: OnlineBook) throws -> URL {
        let ext = book.format.lowercased() == "pdf" ? "pdf" : "epub"

        // Validate magic bytes (ZIP = PK, PDF = %P)
        if let fh = FileHandle(forReadingAtPath: tmpFile.path) {
            let magic = fh.readData(ofLength: 4)
            fh.closeFile()
            let isEPUB = magic.count >= 4 && magic[0] == 0x50 && magic[1] == 0x4B
            let isPDF  = magic.count >= 4 && magic[0] == 0x25 && magic[1] == 0x50
            guard isEPUB || isPDF else {
                try? FileManager.default.removeItem(at: tmpFile)
                throw Err.network("下载内容不是有效的 EPUB/PDF 文件（可能是版权保护或链接失效）")
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

// MARK: - Internet Archive metadata models

private struct IAMetadataResp: Codable {
    let files: [IAFile]?
}
private struct IAFile: Codable {
    let name: String
    let source: String?   // "original" | "derivative" | "metadata"
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

// MARK: - Standard Ebooks OPDS/Atom parser

private final class OPDSAtomParser: NSObject, XMLParserDelegate {
    private static let seBase = "https://standardebooks.org"

    var books: [OnlineBook] = []

    private var inEntry    = false
    private var inAuthor   = false
    private var currentEl  = ""
    private var title      = ""
    private var authorName = ""
    private var entryId    = ""
    private var epubHref: String?
    private var coverHref: String?
    private var updatedYear: Int?

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        currentEl = elementName
        switch elementName {
        case "entry":
            inEntry    = true
            title      = ""
            authorName = ""
            entryId    = ""
            epubHref   = nil
            coverHref  = nil
            updatedYear = nil
        case "author":
            inAuthor = true
        case "link" where inEntry:
            let rel  = attributes["rel"] ?? ""
            let type = attributes["type"] ?? ""
            let href = attributes["href"] ?? ""
            if type == "application/epub+zip" || rel.contains("acquisition") {
                if type == "application/epub+zip" {
                    epubHref = href
                }
            }
            if rel.contains("image") && !rel.contains("thumbnail") {
                coverHref = href
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        switch currentEl {
        case "title" where inEntry:     title      += s
        case "name"  where inAuthor:    authorName += s
        case "id"    where inEntry:     entryId    += s
        case "updated" where inEntry:
            if let year = Int(s.prefix(4)) { updatedYear = year }
        default: break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "author": inAuthor = false
        case "entry":
            if inEntry, !title.isEmpty, let href = epubHref {
                let base = Self.seBase
                let epubURL  = href.hasPrefix("http") ? URL(string: href) : URL(string: base + href)
                let coverURL = coverHref.flatMap {
                    $0.hasPrefix("http") ? URL(string: $0) : URL(string: base + $0)
                }
                // Use last path component of entry id as unique id
                let id = entryId.isEmpty ? UUID().uuidString : entryId
                    .components(separatedBy: "/").last(where: { !$0.isEmpty }) ?? UUID().uuidString
                books.append(OnlineBook(
                    id: id,
                    title: title,
                    authors: authorName.isEmpty ? [] : [authorName],
                    coverURL: coverURL,
                    year: updatedYear,
                    source: .standardEbooks,
                    downloadURL: epubURL,
                    format: "EPUB"
                ))
            }
            inEntry    = false
            inAuthor   = false
        default: break
        }
        currentEl = ""
    }
}
