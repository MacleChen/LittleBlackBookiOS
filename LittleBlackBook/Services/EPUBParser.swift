import Foundation
import ReadiumShared
import ReadiumStreamer
import UIKit

struct EPUBMetadata {
    var title: String
    var author: String
    var description: String
    var coverImage: UIImage?
}

/// Parses EPUB metadata (title, author, description, cover) using Readium.
/// Renamed to `EPUBMetadataParser` to avoid conflict with `ReadiumStreamer.EPUBParser`.
class EPUBMetadataParser {

    private static func makeOpener() -> (AssetRetriever, PublicationOpener) {
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let publicationOpener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )
        return (assetRetriever, publicationOpener)
    }

    static func parse(url: URL) async -> EPUBMetadata {
        let fallback = EPUBMetadata(
            title: url.deletingPathExtension().lastPathComponent,
            author: "未知作者",
            description: "",
            coverImage: nil
        )

        guard let fileURL = FileURL(url: url) else { return fallback }

        let (assetRetriever, publicationOpener) = makeOpener()

        guard case .success(let asset) = await assetRetriever.retrieve(url: fileURL) else {
            return fallback
        }

        guard case .success(let publication) = await publicationOpener.open(
            asset: asset,
            allowUserInteraction: false
        ) else {
            return fallback
        }

        let title  = publication.metadata.title.nilIfEmpty ?? fallback.title
        let author = publication.metadata.authors.first?.name.nilIfEmpty ?? fallback.author
        let desc   = publication.metadata.description ?? ""
        let cover  = try? await publication.cover().get()

        return EPUBMetadata(title: title, author: author, description: desc, coverImage: cover)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
