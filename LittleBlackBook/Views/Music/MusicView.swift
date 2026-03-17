import SwiftUI
import UniformTypeIdentifiers

struct MusicView: View {
    @EnvironmentObject var musicStore: MusicStore
    @StateObject private var vm = MusicViewModel()
    @ObservedObject private var player = MusicPlayer.shared

    @State private var showImportPicker = false
    @State private var showMusicCategories = false
    @State private var detailTrack: Track? = nil
    @State private var showPlayer   = false
    @State private var showOnlineMusic = false

    // Supported audio types (natively playable on iOS)
    private let audioTypes: [UTType] = [
        UTType(filenameExtension: "mp3")  ?? .audio,
        UTType(filenameExtension: "m4a")  ?? .audio,
        UTType(filenameExtension: "aac")  ?? .audio,
        UTType(filenameExtension: "wav")  ?? .audio,
        UTType(filenameExtension: "flac") ?? .audio,
        UTType(filenameExtension: "aiff") ?? .audio,
        UTType(filenameExtension: "aif")  ?? .audio,
        UTType(filenameExtension: "caf")  ?? .audio,
        UTType(filenameExtension: "alac") ?? .audio,
        UTType(filenameExtension: "mp4")  ?? .audio,
        UTType(filenameExtension: "opus") ?? .audio,
        UTType(filenameExtension: "ogg")  ?? .audio,
        // Note: KGM/NCM are DRM-encrypted formats and cannot be played by the system
        UTType(filenameExtension: "kgm")  ?? .data,
        UTType(filenameExtension: "ncm")  ?? .data,
    ]

    var body: some View {
        NavigationStack {
            Group {
                if vm.filteredTracks.isEmpty {
                    emptyState
                } else {
                    trackList
                }
            }
            .navigationTitle("我的音乐")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .searchable(text: $vm.searchText, prompt: "搜索歌曲、艺术家、专辑")
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top) { categoryFilterBar }
        }
        .sheet(item: $detailTrack) { track in
            TrackDetailView(track: track)
                .environmentObject(musicStore)
        }
        .sheet(isPresented: $showPlayer) {
            MusicPlayerView()
        }
        .sheet(isPresented: $showOnlineMusic) {
            OnlineMusicView()
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: audioTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): urls.forEach { vm.importTrack(from: $0) }
            case .failure(let e):   vm.importError = e.localizedDescription
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { vm.importError != nil },
            set: { if !$0 { vm.importError = nil } }
        )) {
            Button("确定", role: .cancel) { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "")
        }
        .alert("播放失败", isPresented: Binding(
            get: { player.unsupportedFormatError != nil },
            set: { if !$0 { player.unsupportedFormatError = nil } }
        )) {
            Button("确定", role: .cancel) { player.unsupportedFormatError = nil }
        } message: {
            Text(player.unsupportedFormatError ?? "")
        }
    }

    // MARK: - Track List

    private var trackList: some View {
        List {
            ForEach(vm.filteredTracks) { track in
                TrackRowView(
                    track: track,
                    isPlaying: player.currentTrack?.id == track.id && player.isPlaying,
                    onPlay: {
                        playTrack(track)
                    },
                    onDetail:   { detailTrack = track },
                    onFavorite: { vm.toggleFavorite(track) },
                    onDelete:   { vm.deleteTrack(track) }
                )
                .listRowBackground(Color(.secondarySystemGroupedBackground))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading) {
                    Button {
                        vm.toggleFavorite(track)
                    } label: {
                        Label(track.isFavorite ? "取消" : "收藏",
                              systemImage: track.isFavorite ? "heart.slash" : "heart")
                    }
                    .tint(.pink)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { vm.deleteTrack(track) } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无音乐", systemImage: "music.note.list")
        } description: {
            Text("点击右上角 + 按钮导入音乐文件")
        } actions: {
            Button { showImportPicker = true } label: {
                Label("导入音乐", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Category Filter

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                MusicFilterChip(title: "全部", icon: "music.note.list",
                           isSelected: vm.selectedCategory == nil,
                           color: .accentColor) { vm.selectedCategory = nil }
                ForEach(musicStore.categories) { cat in
                    MusicFilterChip(title: cat.name, icon: cat.icon,
                               isSelected: vm.selectedCategory?.id == cat.id,
                               color: Color(hex: cat.colorHex)) {
                        vm.selectedCategory = vm.selectedCategory?.id == cat.id ? nil : cat
                    }
                }
                Button { showMusicCategories = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape").font(.system(size: 12, weight: .medium))
                        Text("管理").font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color(.tertiarySystemFill))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showMusicCategories) {
            MusicCategoriesView().environmentObject(musicStore)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showOnlineMusic = true } label: {
                Image(systemName: "globe.badge.chevron.backward")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(MusicViewModel.SortOption.allCases, id: \.self) { opt in
                    Button { vm.sortOption = opt } label: {
                        HStack {
                            Text(opt.rawValue)
                            if vm.sortOption == opt { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle").symbolRenderingMode(.hierarchical)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showImportPicker = true } label: {
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 22))
            }
        }
    }

    // MARK: - Play

    private func playTrack(_ track: Track) {
        vm.recordPlay(track)
        MusicPlayer.shared.play(track, queue: vm.filteredTracks)
    }
}

// MARK: - Filter Chip (music-specific to avoid naming conflict)

struct MusicFilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isSelected ? color : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
