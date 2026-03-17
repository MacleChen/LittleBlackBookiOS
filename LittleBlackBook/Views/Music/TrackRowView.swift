import SwiftUI

struct TrackRowView: View {
    let track: Track
    let isPlaying: Bool
    var onPlay:      (() -> Void)? = nil
    var onDetail:    (() -> Void)? = nil
    var onFavorite:  (() -> Void)? = nil
    var onDelete:    (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            artworkView
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if isPlaying {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(0.35))
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    }
                }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isPlaying ? Color.accentColor : .primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if !track.album.isEmpty {
                        Text("·").font(.system(size: 12)).foregroundStyle(.tertiary)
                        Text(track.album)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Duration + Favorite
            VStack(alignment: .trailing, spacing: 4) {
                Text(track.durationString)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                if track.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.pink)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onPlay?() }
        .contextMenu {
            Button { onDetail?() } label: {
                Label("查看详情", systemImage: "info.circle")
            }
            Button { onFavorite?() } label: {
                Label(track.isFavorite ? "取消收藏" : "收藏",
                      systemImage: track.isFavorite ? "heart.slash" : "heart")
            }
            Divider()
            Button(role: .destructive) { onDelete?() } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let url = track.artworkURL, let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            defaultArtwork
        }
    }

    private var defaultArtwork: some View {
        let colors: [Color] = [.indigo, .teal, .orange, .pink, .purple, .blue, .green]
        let color = colors[abs(track.title.hashValue) % colors.count]
        return LinearGradient(colors: [color, color.opacity(0.6)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.9)))
    }
}
