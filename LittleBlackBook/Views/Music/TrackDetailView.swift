import SwiftUI

struct TrackDetailView: View {
    @EnvironmentObject var musicStore: MusicStore
    @Environment(\.dismiss) private var dismiss
    @State var track: Track
    @State private var isEditing = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerSection.padding(.bottom, 24)
                    statsRow.padding(.horizontal, 20).padding(.bottom, 24)
                    categorySection.padding(.horizontal, 20).padding(.bottom, 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { isEditing = true } label: {
                            Label("编辑信息", systemImage: "pencil")
                        }
                        Button { toggleFavorite() } label: {
                            Label(track.isFavorite ? "取消收藏" : "收藏",
                                  systemImage: track.isFavorite ? "heart.slash" : "heart")
                        }
                        Divider()
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("删除歌曲", systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                playButton
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $isEditing) {
            TrackEditSheet(track: $track, onSave: { musicStore.updateTrack(track) })
        }
        .confirmationDialog("确认删除《\(track.title)》？", isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                musicStore.deleteTrack(track)
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            artworkView.frame(maxWidth: .infinity).frame(height: 260)
                .clipped().overlay(.ultraThinMaterial)

            HStack(alignment: .bottom, spacing: 16) {
                artworkView
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title).font(.title3.bold()).lineLimit(2)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                    if !track.album.isEmpty {
                        Text(track.album).font(.caption).foregroundStyle(.tertiary)
                    }
                    if track.isFavorite {
                        Label("已收藏", systemImage: "heart.fill")
                            .font(.caption).foregroundStyle(.pink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: track.durationString,    label: "时长",   icon: "clock")
            Divider().frame(height: 40)
            statItem(value: "\(track.playCount)",    label: "播放次数", icon: "play.circle")
            Divider().frame(height: 40)
            statItem(
                value: track.lastPlayedDate.map { $0.formatted(.relative(presentation: .named)) } ?? "未播放",
                label: "上次播放", icon: "calendar"
            )
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Color.accentColor)
            Text(value).font(.system(size: 13, weight: .semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("分类", systemImage: "folder").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    categoryChip(nil)
                    ForEach(musicStore.categories) { cat in categoryChip(cat) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func categoryChip(_ cat: MusicCategory?) -> some View {
        let isSelected = track.categoryId == cat?.id
        let color = cat.map { Color(hex: $0.colorHex) } ?? Color.secondary
        return Button {
            track.categoryId = cat?.id
            musicStore.updateTrack(track)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat?.icon ?? "tray").font(.caption)
                Text(cat?.name ?? "未分类").font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isSelected ? color : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Play Button

    private var playButton: some View {
        Button {
            MusicPlayer.shared.play(track, queue: musicStore.tracks)
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("播放")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Color.accentColor).foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artworkView: some View {
        if let url = track.artworkURL, let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            let colors: [Color] = [.indigo, .teal, .orange, .pink, .purple, .blue, .green]
            let color = colors[abs(track.title.hashValue) % colors.count]
            LinearGradient(colors: [color, color.opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(Image(systemName: "music.note")
                    .font(.system(size: 44)).foregroundStyle(.white.opacity(0.8)))
        }
    }

    private func toggleFavorite() {
        track.isFavorite.toggle()
        musicStore.updateTrack(track)
    }
}

// MARK: - Track Edit Sheet

struct TrackEditSheet: View {
    @Binding var track: Track
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title  = ""
    @State private var artist = ""
    @State private var album  = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    LabeledContent("歌名") {
                        TextField("歌名", text: $title).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("艺术家") {
                        TextField("艺术家", text: $artist).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("专辑") {
                        TextField("专辑", text: $album).multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("编辑信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear { title = track.title; artist = track.artist; album = track.album }
        }
    }

    private func save() {
        if !title.trimmingCharacters(in: .whitespaces).isEmpty  { track.title  = title.trimmingCharacters(in: .whitespaces) }
        if !artist.trimmingCharacters(in: .whitespaces).isEmpty { track.artist = artist.trimmingCharacters(in: .whitespaces) }
        track.album = album.trimmingCharacters(in: .whitespaces)
        onSave()
        dismiss()
    }
}
