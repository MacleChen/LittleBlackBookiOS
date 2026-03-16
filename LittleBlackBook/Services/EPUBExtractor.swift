import Foundation
import ZIPFoundation

/// Extracts an EPUB (zip) to Caches/EPUBExtracted/{bookID}/ and returns the
/// ordered list of spine HTML file URLs.
class EPUBExtractor {

    // MARK: - Public

    struct ExtractionResult {
        let extractDir: URL
        let spineItems: [SpineItem]   // ordered chapters
    }

    struct SpineItem {
        let id: String
        let url: URL
        let title: String?
    }

    static func extract(book: Book) throws -> ExtractionResult {
        let dest = extractionDir(for: book)

        // Re-use if already extracted
        if FileManager.default.fileExists(atPath: dest.path) {
            return try buildResult(extractDir: dest, epubURL: book.fileURL, reparse: true)
        }

        guard let archive = try? Archive(url: book.fileURL, accessMode: .read) else {
            throw ExtractorError.cannotOpenArchive
        }

        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        // Extract every entry
        for entry in archive {
            let entryDest = dest.appendingPathComponent(entry.path)
            let parentDir = entryDest.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            if entry.type == .file {
                _ = try? archive.extract(entry, to: entryDest)
            }
        }

        return try buildResult(extractDir: dest, epubURL: book.fileURL, reparse: false)
    }

    static func clearCache(for book: Book) {
        try? FileManager.default.removeItem(at: extractionDir(for: book))
    }

    // MARK: - Private

    private static func extractionDir(for book: Book) -> URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EPUBExtracted")
            .appendingPathComponent(book.id.uuidString)
    }

    private static func buildResult(extractDir: URL, epubURL: URL, reparse: Bool) throws -> ExtractionResult {
        // Read container.xml
        let containerURL = extractDir.appendingPathComponent("META-INF/container.xml")
        guard let containerData = try? Data(contentsOf: containerURL) else {
            throw ExtractorError.missingContainer
        }
        let containerParser = SimpleXMLParser(data: containerData)
        containerParser.parse()
        guard let opfPath = containerParser.attributes(forElement: "rootfile")?["full-path"] else {
            throw ExtractorError.missingOPF
        }

        // Read OPF
        let opfURL = extractDir.appendingPathComponent(opfPath)
        guard let opfData = try? Data(contentsOf: opfURL) else {
            throw ExtractorError.missingOPF
        }
        let opfParser = OPFParser(data: opfData)
        opfParser.parse()

        let basePath = (opfPath as NSString).deletingLastPathComponent

        // Build spine items
        var items: [SpineItem] = []
        for (id, href, title) in opfParser.spineItems {
            let path = basePath.isEmpty ? href : "\(basePath)/\(href)"
            let fileURL = extractDir.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                items.append(SpineItem(id: id, url: fileURL, title: title))
            }
        }

        if items.isEmpty { throw ExtractorError.emptySpine }

        return ExtractionResult(extractDir: extractDir, spineItems: items)
    }

    enum ExtractorError: LocalizedError {
        case cannotOpenArchive, missingContainer, missingOPF, emptySpine
        var errorDescription: String? {
            switch self {
            case .cannotOpenArchive: return "无法打开 EPUB 文件"
            case .missingContainer: return "找不到 container.xml"
            case .missingOPF:       return "找不到 OPF 文件"
            case .emptySpine:       return "书脊为空，无章节可读"
            }
        }
    }
}

// MARK: - OPF-specific Parser (manifest + spine)

private class OPFParser: NSObject, XMLParserDelegate {
    private let data: Data

    /// manifest: id -> (href, mediaType)
    private var manifest: [String: (href: String, type: String)] = [:]
    /// spine: ordered idref list
    private var spineOrder: [String] = []
    /// nav / toc: id -> title
    private var navTitles: [String: String] = [:]

    /// Result: (id, href, title?)
    var spineItems: [(id: String, href: String, title: String?)] = []

    init(data: Data) { self.data = data }

    func parse() {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        buildSpine()
    }

    private func buildSpine() {
        for idref in spineOrder {
            if let item = manifest[idref] {
                spineItems.append((id: idref, href: item.href, title: navTitles[idref]))
            }
        }
    }

    func parser(_ p: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attr: [String: String]) {
        let local = localName(name)
        switch local {
        case "item":
            if let id = attr["id"], let href = attr["href"] {
                manifest[id] = (href: href, type: attr["media-type"] ?? "")
            }
        case "itemref":
            if let idref = attr["idref"] {
                spineOrder.append(idref)
            }
        default: break
        }
    }

    private func localName(_ n: String) -> String {
        n.contains(":") ? String(n.split(separator: ":").last ?? Substring(n)) : n
    }
}
