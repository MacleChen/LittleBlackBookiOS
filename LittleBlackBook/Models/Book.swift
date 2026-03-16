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
}

extension FileManager {
    var documentsDirectory: URL {
        urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
