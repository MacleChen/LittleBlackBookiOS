import Foundation
import AVFoundation
import UIKit
import Combine

class MusicStore: ObservableObject {
    static let shared = MusicStore()

    @Published var tracks: [Track] = []
    @Published var categories: [MusicCategory] = []

    private let tracksKey    = "lbb_tracks"
    private let categoriesKey = "lbb_music_categories"

    private init() {
        createDirectories()
        load()
        if categories.isEmpty {
            categories = MusicCategory.defaultCategories
            saveCategories()
        }
    }

    // MARK: - Directories

    private func createDirectories() {
        let fm = FileManager.default
        let base = fm.documentsDirectory
        [base.appendingPathComponent("Music"),
         base.appendingPathComponent("MusicArtwork")].forEach {
            try? fm.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    // MARK: - Load / Save

    private func load() {
        if let data = UserDefaults.standard.data(forKey: tracksKey),
           let decoded = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = decoded
        }
        if let data = UserDefaults.standard.data(forKey: categoriesKey),
           let decoded = try? JSONDecoder().decode([MusicCategory].self, from: data) {
            categories = decoded
        }
    }

    private func saveTracks() {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: tracksKey)
        }
    }

    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: categoriesKey)
        }
    }

    // MARK: - Track CRUD

    @discardableResult
    func addTrack(from sourceURL: URL, category: MusicCategory? = nil) async throws -> Track {
        let fm = FileManager.default
        let destDir = fm.documentsDirectory.appendingPathComponent("Music")
        var destName = sourceURL.lastPathComponent
        var destURL = destDir.appendingPathComponent(destName)

        var counter = 1
        while fm.fileExists(atPath: destURL.path) {
            let base = sourceURL.deletingPathExtension().lastPathComponent
            let ext  = sourceURL.pathExtension
            destName = "\(base)_\(counter).\(ext)"
            destURL  = destDir.appendingPathComponent(destName)
            counter += 1
        }

        try fm.copyItem(at: sourceURL, to: destURL)

        // KGM/VPR files are encrypted — skip AVURLAsset (it can't read them)
        let encryptedExts = ["kgm", "kgma", "vpr"]
        let isEncrypted = encryptedExts.contains(destURL.pathExtension.lowercased())
        let meta = isEncrypted
            ? TrackMeta(
                title:    destURL.deletingPathExtension().lastPathComponent,
                artist:   "未知艺术家",
                album:    "",
                duration: 0,
                artwork:  nil
              )
            : await extractMetadata(from: destURL)

        var artworkName: String? = nil
        if let img = meta.artwork, let jpeg = img.jpegData(compressionQuality: 0.85) {
            let name = UUID().uuidString + ".jpg"
            let artworkURL = fm.documentsDirectory
                .appendingPathComponent("MusicArtwork")
                .appendingPathComponent(name)
            try? jpeg.write(to: artworkURL)
            artworkName = name
        }

        let track = Track(
            title:            meta.title,
            artist:           meta.artist,
            album:            meta.album,
            duration:         meta.duration,
            fileName:         destName,
            artworkImageName: artworkName,
            categoryId:       category?.id
        )

        await MainActor.run {
            tracks.append(track)
            saveTracks()
        }
        return track
    }

    func updateTrack(_ track: Track) {
        if let idx = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[idx] = track
            saveTracks()
        }
    }

    func deleteTrack(_ track: Track) {
        try? FileManager.default.removeItem(at: track.fileURL)
        if let name = track.artworkImageName {
            let url = FileManager.default.documentsDirectory
                .appendingPathComponent("MusicArtwork")
                .appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
        tracks.removeAll { $0.id == track.id }
        saveTracks()
    }

    func tracks(in category: MusicCategory?) -> [Track] {
        guard let cat = category else { return tracks }
        return tracks.filter { $0.categoryId == cat.id }
    }

    // MARK: - Category CRUD

    func addCategory(_ category: MusicCategory) {
        categories.append(category)
        saveCategories()
    }

    func updateCategory(_ category: MusicCategory) {
        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
            categories[idx] = category
            saveCategories()
        }
    }

    func deleteCategory(_ category: MusicCategory) {
        for i in tracks.indices where tracks[i].categoryId == category.id {
            tracks[i].categoryId = nil
        }
        saveTracks()
        categories.removeAll { $0.id == category.id }
        saveCategories()
    }

    func trackCount(for category: MusicCategory) -> Int {
        tracks.filter { $0.categoryId == category.id }.count
    }

    // MARK: - Metadata extraction

    private struct TrackMeta {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var artwork: UIImage?
    }

    private func extractMetadata(from url: URL) async -> TrackMeta {
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let asset = AVURLAsset(url: url)

        async let durationValue = asset.load(.duration)
        async let metadataValue = asset.load(.commonMetadata)

        let duration = (try? await durationValue)?.seconds ?? 0
        let metadata = (try? await metadataValue) ?? []

        func stringValue(for key: AVMetadataKey) -> String? {
            metadata.first(where: { $0.commonKey == key })?.stringValue
        }

        let title  = stringValue(for: .commonKeyTitle)?.nilIfEmpty  ?? fallbackTitle
        let artist = stringValue(for: .commonKeyArtist)?.nilIfEmpty ?? "未知艺术家"
        let album  = stringValue(for: .commonKeyAlbumName)?.nilIfEmpty ?? ""

        var artwork: UIImage? = nil
        if let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }),
           let data = try? await item.load(.dataValue) {
            artwork = UIImage(data: data)
        }

        return TrackMeta(title: title, artist: artist, album: album,
                         duration: duration, artwork: artwork)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
