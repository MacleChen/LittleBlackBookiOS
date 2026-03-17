import SwiftUI
import UniformTypeIdentifiers

class MusicViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedCategory: MusicCategory? = nil
    @Published var importError: String? = nil
    @Published var sortOption: SortOption = .dateAdded

    enum SortOption: String, CaseIterable {
        case dateAdded = "添加时间"
        case title     = "歌名"
        case artist    = "艺术家"
        case lastPlayed = "最近播放"
        case playCount = "播放次数"
    }

    private let store: MusicStore

    init(store: MusicStore = .shared) {
        self.store = store
    }

    var filteredTracks: [Track] {
        var result = store.tracks

        if let cat = selectedCategory {
            result = result.filter { $0.categoryId == cat.id }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q)  ||
                $0.artist.lowercased().contains(q) ||
                $0.album.lowercased().contains(q)
            }
        }

        switch sortOption {
        case .dateAdded:  result.sort { $0.addedDate > $1.addedDate }
        case .title:      result.sort { $0.title < $1.title }
        case .artist:     result.sort { $0.artist < $1.artist }
        case .lastPlayed:
            result.sort { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
        case .playCount:  result.sort { $0.playCount > $1.playCount }
        }

        return result
    }

    func importTrack(from url: URL, category: MusicCategory? = nil) {
        let accessing = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                try await store.addTrack(from: url, category: category ?? selectedCategory)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    func deleteTrack(_ track: Track) { store.deleteTrack(track) }

    func toggleFavorite(_ track: Track) {
        var t = track; t.isFavorite.toggle(); store.updateTrack(t)
    }

    func recordPlay(_ track: Track) {
        var t = track
        t.playCount += 1
        t.lastPlayedDate = Date()
        store.updateTrack(t)
    }
}
