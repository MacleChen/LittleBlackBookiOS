import Foundation
import UIKit
import ZIPFoundation

struct EPUBMetadata {
    var title: String
    var author: String
    var description: String
    var coverImage: UIImage?
}

class EPUBParser {

    static func parse(url: URL) -> EPUBMetadata {
        var meta = EPUBMetadata(
            title: url.deletingPathExtension().lastPathComponent,
            author: "未知作者",
            description: "",
            coverImage: nil
        )
        guard let archive = try? Archive(url: url, accessMode: .read) else { return meta }
        guard let opfPath = findOPFPath(in: archive) else { return meta }
        parseOPF(path: opfPath, archive: archive, meta: &meta)
        return meta
    }

    // MARK: - Find OPF path via META-INF/container.xml

    private static func findOPFPath(in archive: Archive) -> String? {
        guard let entry = archive["META-INF/container.xml"] else { return nil }
        var data = Data()
        _ = try? archive.extract(entry) { data.append($0) }
        let parser = SimpleXMLParser(data: data)
        parser.parse()
        // <rootfile full-path="OEBPS/content.opf" .../>
        return parser.attributes(forElement: "rootfile")?["full-path"]
    }

    // MARK: - Parse OPF

    private static func parseOPF(path: String, archive: Archive, meta: inout EPUBMetadata) {
        guard let entry = archive[path] else { return }
        var data = Data()
        _ = try? archive.extract(entry) { data.append($0) }

        let parser = SimpleXMLParser(data: data)
        parser.parse()

        if let title = parser.textContent(forElement: "dc:title") ?? parser.textContent(forElement: "title"),
           !title.trimmingCharacters(in: .whitespaces).isEmpty {
            meta.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let author = parser.textContent(forElement: "dc:creator") ?? parser.textContent(forElement: "creator"),
           !author.trimmingCharacters(in: .whitespaces).isEmpty {
            meta.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let desc = parser.textContent(forElement: "dc:description") ?? parser.textContent(forElement: "description") {
            meta.description = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find cover image href
        let basePath = (path as NSString).deletingLastPathComponent
        if let coverHref = findCoverHref(parser: parser, basePath: basePath) {
            let coverPath = basePath.isEmpty ? coverHref : "\(basePath)/\(coverHref)"
            if let imgEntry = archive[coverPath] {
                var imgData = Data()
                _ = try? archive.extract(imgEntry) { imgData.append($0) }
                meta.coverImage = UIImage(data: imgData)
            }
        }
    }

    private static func findCoverHref(parser: SimpleXMLParser, basePath: String) -> String? {
        // 1. <meta name="cover" content="cover-id"/> then find item by id
        if let coverId = parser.metaContent(forName: "cover") {
            if let href = parser.manifestHref(forId: coverId) { return href }
        }
        // 2. <item properties="cover-image" href="..."/>
        if let href = parser.manifestHref(forProperty: "cover-image") { return href }
        // 3. item id contains "cover"
        if let href = parser.manifestHref(containingIdSubstring: "cover") { return href }
        return nil
    }
}

// MARK: - Simple SAX XML Parser

/// Lightweight SAX parser that collects element text, attributes, and manifest items.
class SimpleXMLParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var elementStack: [String] = []
    private var currentText: String = ""

    // element name (local) -> first occurrence attributes
    private var elementAttributes: [String: [String: String]] = [:]
    // element name (local) -> first text content
    private var elementText: [String: String] = [:]
    // manifest: id -> href
    private var manifestItems: [[String: String]] = []
    // meta name -> content
    private var metaMap: [String: String] = [:]

    init(data: Data) { self.data = data }

    func parse() {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
    }

    // MARK: - Query API

    func attributes(forElement name: String) -> [String: String]? {
        return elementAttributes[name] ?? elementAttributes[name.lowercased()]
    }

    func textContent(forElement name: String) -> String? {
        return elementText[name] ?? elementText[name.lowercased()]
    }

    func metaContent(forName name: String) -> String? {
        return metaMap[name]
    }

    func manifestHref(forId id: String) -> String? {
        manifestItems.first { $0["id"] == id }?["href"]
    }

    func manifestHref(forProperty prop: String) -> String? {
        manifestItems.first { $0["properties"] == prop }?["href"]
    }

    func manifestHref(containingIdSubstring sub: String) -> String? {
        manifestItems.first { ($0["id"] ?? "").lowercased().contains(sub.lowercased()) }?["href"]
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        let local = localName(elementName)
        elementStack.append(local)
        currentText = ""

        if elementAttributes[local] == nil {
            elementAttributes[local] = attributes
        }

        if local == "item" {
            manifestItems.append(attributes)
        }

        // <meta name="cover" content="cover-id"/>
        if local == "meta", let name = attributes["name"], let content = attributes["content"] {
            metaMap[name] = content
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = localName(elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, elementText[local] == nil {
            elementText[local] = text
        }
        // Also store with qualified name for dc:title etc.
        if let qn = qName, !qn.isEmpty, elementText[qn] == nil, !text.isEmpty {
            elementText[qn] = text
        }
        elementStack.removeLast()
        currentText = ""
    }

    private func localName(_ name: String) -> String {
        // Strip namespace prefix: "dc:title" -> "title", but keep original too
        if name.contains(":") {
            return String(name.split(separator: ":").last ?? Substring(name))
        }
        return name
    }
}
