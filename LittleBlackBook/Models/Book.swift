import Foundation
import UIKit

struct Book: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var author: String
    var description: String
    var categoryId: UUID?
    var fileName: String          // stored in Documents/Books/
    var coverImageName: String?   // stored in Documents/Covers/
    var addedDate: Date = Date()
    var lastReadDate: Date?
    var readingProgress: Double = 0.0  // 0.0 ~ 1.0
    var isFinished: Bool = false
    var finishedDate: Date?
    var isFavorite: Bool = false
    var tags: [String] = []
    var notes: String = ""

    var coverImageURL: URL? {
        guard let name = coverImageName else { return nil }
        return FileManager.default.documentsDirectory
            .appendingPathComponent("Covers")
            .appendingPathComponent(name)
    }

    var fileURL: URL {
        FileManager.default.documentsDirectory
            .appendingPathComponent("Books")
            .appendingPathComponent(fileName)
    }

    /// Detected format based on file extension
    var format: BookFormat {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "epub":        return .epub
        case "txt":         return .txt
        case "pdf":         return .pdf
        case "mobi", "azw", "azw3": return .unsupported("MOBI/AZW")
        case "cbz", "cbr":  return .unsupported("CBZ/CBR")
        default:            return .unsupported((fileName as NSString).pathExtension.uppercased())
        }
    }
}

enum BookFormat {
    case epub, txt, pdf
    case unsupported(String)   // format name for the error message
}

extension FileManager {
    var documentsDirectory: URL {
        urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
