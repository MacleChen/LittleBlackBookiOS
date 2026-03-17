import SwiftUI

struct OnlineMusicView: View {
    @StateObject private var vm = OnlineMusicViewModel()
    @ObservedObject private var player = MusicPlayer.shared

    var body: some View {
        NavigationStack {
            Group {
                if vm.isSearching {
                    ProgressView("搜索中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.songs.isEmpty && !vm.searchText.isEmpty {
                    emptyState
                } else if vm.songs.isEmpty {
                    placeholderState
                } else {
                    songList
                }
            }
            .navigationTitle("在线音乐")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $vm.searchText, prompt: "搜索歌曲、歌手、专辑")
            .onSubmit(of: .search) { Task { await vm.search() } }
            .background(Color(.systemGroupedBackground))
        }
        .alert("提示", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Song List

    private var songList: some View {
        List {
            ForEach(vm.songs) { song in
                OnlineSongRow(
                    song: song,
                    isPlaying: player.currentTrack?.title == song.title && player.isPlaying,
                    isLoading: vm.isLoadingId == song.id,
                    isImported: vm.importedIds.contains(song.id),
                    onPlay: { Task { await vm.playOnline(song: song) } },
                    onDownload: { Task { await vm.downloadToLibrary(song: song) } }
                )
                .listRowBackground(Color(.secondarySystemGroupedBackground))
                .listRowSeparator(.hidden)
                .onAppear {
                    if song.id == vm.songs.last?.id {
                        Task { await vm.loadMore() }
                    }
                }
            }
            if vm.hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView.search(text: vm.searchText)
    }

    private var placeholderState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("搜索歌曲、歌手或专辑")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("数据来源：网易云音乐（个人非商业用途）")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - OnlineSongRow

struct OnlineSongRow: View {
    let song: OnlineSong
    let isPlaying: Bool
    let isLoading: Bool
    let isImported: Bool
    let onPlay: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Cover art
            AsyncImage(url: song.coverURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(.tertiarySystemFill)
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(isPlaying ? Color.accentColor : .primary)
                HStack(spacing: 4) {
                    Text(song.artist)
                    Text("·")
                    Text(song.album)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            // Duration
            Text(durationText(song.duration))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 36)

            // Actions
            if isLoading {
                ProgressView().frame(width: 32)
            } else {
                HStack(spacing: 6) {
                    Button(action: onPlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onDownload) {
                        Image(systemName: isImported ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isImported ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isImported)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "--:--" }
        let t = Int(seconds)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
