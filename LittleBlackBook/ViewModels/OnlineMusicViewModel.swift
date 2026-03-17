import SwiftUI

@MainActor
final class OnlineMusicViewModel: ObservableObject {
    @Published var songs: [OnlineSong] = []
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var isLoadingId: String? = nil   // which song is loading (play/download)
    @Published var errorMessage: String? = nil
    @Published var importedIds: Set<String> = []  // songs already imported to local library
    @Published var currentPage = 1
    @Published var hasMore = false

    private var lastQuery = ""

    func search() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        lastQuery = q
        isSearching = true
        errorMessage = nil
        currentPage = 1
        do {
            let results = try await OnlineMusicService.shared.search(query: q, page: 1)
            songs = results
            hasMore = results.count >= 20
        } catch {
            errorMessage = error.localizedDescription
            songs = []
        }
        isSearching = false
    }

    func loadMore() async {
        guard !isSearching, hasMore else { return }
        currentPage += 1
        do {
            let more = try await OnlineMusicService.shared.search(query: lastQuery, page: currentPage)
            songs.append(contentsOf: more)
            hasMore = more.count >= 20
        } catch {
            currentPage -= 1
        }
    }

    /// Download + import into local MusicStore, then play immediately
    func playOnline(song: OnlineSong) async {
        guard isLoadingId == nil else { return }
        isLoadingId = song.id
        errorMessage = nil
        do {
            let tmpURL = try await OnlineMusicService.shared.downloadAudio(song: song)
            let track = try await MusicStore.shared.addTrack(from: tmpURL)
            try? FileManager.default.removeItem(at: tmpURL)
            importedIds.insert(song.id)
            MusicPlayer.shared.play(track)
        } catch {
            errorMessage = "播放失败：\(error.localizedDescription)"
        }
        isLoadingId = nil
    }

    /// Download + import into local MusicStore (without playing)
    func downloadToLibrary(song: OnlineSong) async {
        guard isLoadingId == nil else { return }
        isLoadingId = song.id
        errorMessage = nil
        do {
            let tmpURL = try await OnlineMusicService.shared.downloadAudio(song: song)
            try await MusicStore.shared.addTrack(from: tmpURL)
            try? FileManager.default.removeItem(at: tmpURL)
            importedIds.insert(song.id)
        } catch {
            errorMessage = "下载失败：\(error.localizedDescription)"
        }
        isLoadingId = nil
    }
}
