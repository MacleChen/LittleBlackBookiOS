import SwiftUI

struct MusicPlayerView: View {
    @ObservedObject private var player = MusicPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isDraggingSeek = false
    @State private var seekValue: Double = 0

    var body: some View {
        NavigationStack {
            ZStack {
                // Blurred background
                artworkImage
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 60)
                    .opacity(0.5)
                Color(.systemBackground).opacity(0.7).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Large artwork
                    artworkImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: 260, height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                        .padding(.top, 20)
                        .scaleEffect(player.isPlaying ? 1.0 : 0.88)
                        .animation(.spring(response: 0.4), value: player.isPlaying)

                    // Title & Artist
                    VStack(spacing: 6) {
                        Text(player.currentTrack?.title ?? "未播放")
                            .font(.title2.bold())
                            .lineLimit(1)
                        Text(player.currentTrack?.artist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 28)
                    .padding(.horizontal, 32)

                    // Favorite
                    HStack {
                        Spacer()
                        Button {
                            guard var t = player.currentTrack else { return }
                            t.isFavorite.toggle()
                            MusicStore.shared.updateTrack(t)
                            // Refresh currentTrack reference
                            player.currentTrack?.isFavorite = t.isFavorite
                        } label: {
                            Image(systemName: player.currentTrack?.isFavorite == true ? "heart.fill" : "heart")
                                .font(.system(size: 22))
                                .foregroundStyle(player.currentTrack?.isFavorite == true ? .pink : .secondary)
                        }
                        .padding(.trailing, 32)
                    }
                    .padding(.top, 16)

                    // Seek bar
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { isDraggingSeek ? seekValue : player.currentTime },
                                set: { seekValue = $0 }
                            ),
                            in: 0...(player.duration > 0 ? player.duration : 1),
                            onEditingChanged: { editing in
                                isDraggingSeek = editing
                                if !editing { player.seek(to: seekValue) }
                            }
                        )
                        .tint(.primary)

                        HStack {
                            Text(formatTime(isDraggingSeek ? seekValue : player.currentTime))
                            Spacer()
                            Text(formatTime(player.duration))
                        }
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 24)

                    // Main controls
                    HStack(spacing: 40) {
                        // Shuffle
                        Button { player.isShuffled.toggle() } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 20))
                                .foregroundStyle(player.isShuffled ? .accent : .secondary)
                        }

                        // Previous
                        Button { player.previous() } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 30))
                        }

                        // Play / Pause
                        Button { player.togglePlayPause() } label: {
                            ZStack {
                                Circle().fill(Color.primary).frame(width: 68, height: 68)
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color(.systemBackground))
                                    .offset(x: player.isPlaying ? 0 : 2)
                            }
                        }

                        // Next
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 30))
                        }

                        // Repeat
                        Button { player.cycleRepeat() } label: {
                            Image(systemName: player.repeatMode.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(player.repeatMode.isActive ? .accent : .secondary)
                                .overlay(alignment: .topTrailing) {
                                    if player.repeatMode == .one {
                                        Text("1")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.accent)
                                            .offset(x: 4, y: -4)
                                    }
                                }
                        }
                    }
                    .padding(.top, 28)
                    .padding(.horizontal, 32)

                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
    }

    private var artworkImage: Image {
        if let url = player.currentTrack?.artworkURL,
           let img = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: img)
        }
        let colors: [Color] = [.indigo, .teal, .orange, .pink, .purple, .blue, .green]
        let hash  = player.currentTrack?.title.hashValue ?? 0
        let color = colors[abs(hash) % colors.count]
        return Image(uiImage: gradientImage(color: color))
    }

    private func gradientImage(color: Color) -> UIImage {
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [UIColor(color).cgColor, UIColor(color).withAlphaComponent(0.5).cgColor]
            let grad = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
            ctx.cgContext.drawLinearGradient(grad,
                start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 80),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            let str = "♪" as NSString
            let sz = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(x: (size.width - sz.width) / 2,
                                 y: (size.height - sz.height) / 2), withAttributes: attrs)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(max(0, t))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
