import Foundation

struct Track: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval = 0
    var fileName: String              // stored in Documents/Music/
    var artworkImageName: String?     // stored in Documents/MusicArtwork/
    var categoryId: UUID?
    var addedDate: Date = Date()
    var lastPlayedDate: Date?
    var isFavorite: Bool = false
    var playCount: Int = 0
    var tags: [String] = []

    var fileURL: URL {
        FileManager.default.documentsDirectory
            .appendingPathComponent("Music")
            .appendingPathComponent(fileName)
    }

    var artworkURL: URL? {
        guard let name = artworkImageName else { return nil }
        return FileManager.default.documentsDirectory
            .appendingPathComponent("MusicArtwork")
            .appendingPathComponent(name)
    }

    var durationString: String {
        guard duration > 0 else { return "--:--" }
        let total = Int(duration)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
