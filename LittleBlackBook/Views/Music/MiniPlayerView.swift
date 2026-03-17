import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject private var player = MusicPlayer.shared
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            artworkView
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Title + Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.title ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(player.currentTrack?.artist ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Controls
            if player.isDecrypting {
                ProgressView().scaleEffect(0.8)
                    .frame(width: 60)
            } else {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18))
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            // Thin progress bar
            GeometryReader { geo in
                let progress = player.duration > 0 ? player.currentTime / player.duration : 0
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress, height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let url = player.currentTrack?.artworkURL,
           let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            defaultArtwork
        }
    }

    private var defaultArtwork: some View {
        let color = artworkColor
        return LinearGradient(colors: [color, color.opacity(0.6)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "music.note")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.9)))
    }

    private var artworkColor: Color {
        let colors: [Color] = [.indigo, .teal, .orange, .pink, .purple, .blue, .green]
        let hash = player.currentTrack?.title.hashValue ?? 0
        return colors[abs(hash) % colors.count]
    }
}
