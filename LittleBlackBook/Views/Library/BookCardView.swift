import SwiftUI

struct BookCardView: View {
    let book: Book
    var onDetail:   (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    var onDelete:   (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover
            ZStack(alignment: .topTrailing) {
                coverImage
                    .frame(height: 175)
                    .clipped()

                if book.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }

                // Finished badge
                if book.isFinished {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.green.opacity(0.85), in: Circle())
                        .padding([.bottom, .leading], 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(book.author)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if book.readingProgress > 0 {
                    ProgressView(value: book.readingProgress)
                        .tint(book.isFinished ? .green : Color.accentColor)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .contextMenu {
            Button { onDetail?() } label: {
                Label("查看详情", systemImage: "info.circle")
            }
            Divider()
            Button { onFavorite?() } label: {
                Label(book.isFavorite ? "取消收藏" : "收藏",
                      systemImage: book.isFavorite ? "heart.slash" : "heart")
            }
            Divider()
            Button(role: .destructive) { onDelete?() } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let url = book.coverImageURL, let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            defaultCover
        }
    }

    private var defaultCover: some View {
        LinearGradient(colors: [coverColor, coverColor.opacity(0.6)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(book.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .lineLimit(3)
                }
            )
    }

    private var coverColor: Color {
        let colors: [Color] = [.indigo, .teal, .orange, .pink, .purple, .blue, .green]
        return colors[abs(book.title.hashValue) % colors.count]
    }
}
