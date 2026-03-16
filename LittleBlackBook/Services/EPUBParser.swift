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

class EPUBParser {

    static func parse(url: URL) async -> EPUBMetadata {
        let fallback = EPUBMetadata(
            title: url.deletingPathExtension().lastPathComponent,
            author: "未知作者",
            description: "",
            coverImage: nil
        )

        guard let publication = try? await Streamer().open(
            asset: FileAsset(url: url),
            allowUserInteraction: false
        ) else {
            return fallback
        }

        let title  = publication.metadata.title.nilIfEmpty ?? fallback.title
        let author = publication.metadata.authors.first?.name.nilIfEmpty ?? fallback.author
        let desc   = publication.metadata.description ?? ""
        let cover  = publication.cover   // UIImage? from ReadiumShared

        return EPUBMetadata(title: title, author: author, description: desc, coverImage: cover)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
