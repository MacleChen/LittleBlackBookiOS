import Foundation
import UIKit
import ZIPFoundation

struct EPUBMetadata {
    var title: String
    var author: String
    var description: String
    var coverImage: UIImage?
}

// MARK: - Public Parser

class EPUBMetadataParser {

    /// Parse metadata (title, author, description, cover) from an EPUB file.
    static func parse(url: URL) async -> EPUBMetadata {
        let fallback = EPUBMetadata(
            title: url.deletingPathExtension().lastPathComponent,
            author: "未知作者",
            description: "",
            coverImage: nil
        )
        return (try? await parseInternal(url: url)) ?? fallback
    }

    /// Extract the reading spine (ordered chapter URLs) from an already-unzipped directory.
    static func extractSpine(from dir: URL) throws -> [URL] {
        let containerURL = dir.appendingPathComponent("META-INF/container.xml")
        let containerData = try Data(contentsOf: containerURL)

        let containerHandler = _ContainerXMLHandler()
        let containerParser  = XMLParser(data: containerData)
        containerParser.delegate = containerHandler
        containerParser.parse()

        guard let opfRelPath = containerHandler.opfPath else {
            throw NSError(domain: "EPUBParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "container.xml: rootfile 缺失"])
        }

        let opfURL  = dir.appendingPathComponent(opfRelPath)
        let opfData = try Data(contentsOf: opfURL)
        let opfDir  = opfURL.deletingLastPathComponent()

        let opfHandler = _OPFHandler()
        let opfParser  = XMLParser(data: opfData)
        opfParser.delegate = opfHandler
        opfParser.parse()

        return opfHandler.spineHrefs.map { opfDir.appendingPathComponent($0) }
    }

    // MARK: - Private

    private static func parseInternal(url: URL) async throws -> EPUBMetadata {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw NSError(domain: "EPUBParser", code: 2)
        }

        // 1. Read META-INF/container.xml
        guard let containerEntry = archive["META-INF/container.xml"],
              let containerData  = extractData(from: containerEntry, archive: archive) else {
            throw NSError(domain: "EPUBParser", code: 3)
        }
        let containerHandler = _ContainerXMLHandler()
        let containerParser  = XMLParser(data: containerData)
        containerParser.delegate = containerHandler
        containerParser.parse()

        guard let opfPath = containerHandler.opfPath else {
            throw NSError(domain: "EPUBParser", code: 4)
        }

        // 2. Read OPF
        guard let opfEntry = archive[opfPath],
              let opfData  = extractData(from: opfEntry, archive: archive) else {
            throw NSError(domain: "EPUBParser", code: 5)
        }
        let opfDir = (opfPath as NSString).deletingLastPathComponent

        let opfHandler = _OPFHandler()
        let opfParser  = XMLParser(data: opfData)
        opfParser.delegate = opfHandler
        opfParser.parse()

        // 3. Cover image
        var coverImage: UIImage?
        if let coverRelPath = opfHandler.coverImageHref {
            let fullPath = opfDir.isEmpty ? coverRelPath : "\(opfDir)/\(coverRelPath)"
            if let entry = archive[fullPath],
               let data  = extractData(from: entry, archive: archive) {
                coverImage = UIImage(data: data)
            }
        }

        return EPUBMetadata(
            title:       opfHandler.title.isEmpty       ? "未知书名" : opfHandler.title,
            author:      opfHandler.author.isEmpty      ? "未知作者" : opfHandler.author,
            description: opfHandler.bookDescription,
            coverImage:  coverImage
        )
    }

    private static func extractData(from entry: Entry, archive: Archive) -> Data? {
        var data = Data()
        _ = try? archive.extract(entry) { data.append($0) }
        return data.isEmpty ? nil : data
    }
}

// MARK: - container.xml SAX handler (internal so EPUBReaderView can also use it)

final class _ContainerXMLHandler: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName _: String?,
                attributes: [String: String]) {
        if elementName == "rootfile", opfPath == nil {
            opfPath = attributes["full-path"]
        }
    }
}

// MARK: - OPF SAX handler

final class _OPFHandler: NSObject, XMLParserDelegate {
    var title            = ""
    var author           = ""
    var bookDescription  = ""
    var coverImageHref:  String?
    var spineHrefs:      [String] = []

    private var manifest:    [String: String] = [:]   // id → href
    private var spineIdrefs: [String] = []
    private var coverId:     String?
    private var currentElement = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName _: String?,
                attributes: [String: String]) {
        currentElement = elementName
        switch elementName {
        case "item":
            let id   = attributes["id"]         ?? ""
            let href = attributes["href"]        ?? ""
            manifest[id] = href
            // Cover via properties attribute (EPUB3)
            if attributes["properties"] == "cover-image" { coverImageHref = href }
            // Cover via id naming convention (EPUB2 common)
            if coverImageHref == nil,
               let mt = attributes["media-type"], mt.hasPrefix("image/"),
               (id == "cover" || id.lowercased().contains("cover")) {
                coverImageHref = href
            }
        case "itemref":
            if let idref = attributes["idref"] { spineIdrefs.append(idref) }
        case "meta":
            // EPUB2 cover: <meta name="cover" content="cover-image-id"/>
            if attributes["name"] == "cover", let content = attributes["content"] {
                coverId = content
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        switch currentElement {
        case "dc:title",       "title":       title           += s
        case "dc:creator",    "creator":     author          += s
        case "dc:description","description": bookDescription += s
        default: break
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        spineHrefs = spineIdrefs.compactMap { manifest[$0] }
        if coverImageHref == nil, let cId = coverId {
            coverImageHref = manifest[cId]
        }
    }
}
