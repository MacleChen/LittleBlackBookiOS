import SwiftUI

struct BookDetailView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @State var book: Book
    @State private var isEditing = false
    @State private var showReader = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header: cover + info
                    headerSection
                        .padding(.bottom, 24)

                    // Stats row
                    statsRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Description
                    if !book.description.isEmpty {
                        descriptionSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }

                    // Category picker
                    categorySection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
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
                            Label(book.isFavorite ? "取消收藏" : "收藏",
                                  systemImage: book.isFavorite ? "heart.slash" : "heart")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除书籍", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                readButton
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $isEditing) {
            BookEditView(book: $book)
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showReader) {
            EPUBReaderView(book: $book)
                .environmentObject(store)
        }
        .confirmationDialog("确认删除《\(book.title)》？", isPresented: $showDeleteConfirm,
                             titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                store.deleteBook(book)
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            // Blurred background
            coverImageView
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
                .overlay(.ultraThinMaterial)

            HStack(alignment: .bottom, spacing: 16) {
                // Cover thumbnail
                coverImageView
                    .frame(width: 110, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if book.isFavorite {
                        Label("已收藏", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
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
            statItem(
                value: book.readingProgress > 0
                    ? "\(Int(book.readingProgress * 100))%"
                    : "未读",
                label: "阅读进度",
                icon: "book.pages"
            )
            Divider().frame(height: 40)
            statItem(
                value: book.lastReadDate.map { $0.formatted(.relative(presentation: .named)) } ?? "—",
                label: "上次阅读",
                icon: "clock"
            )
            Divider().frame(height: 40)
            statItem(
                value: book.addedDate.formatted(date: .abbreviated, time: .omitted),
                label: "加入日期",
                icon: "calendar"
            )
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("简介", systemImage: "text.alignleft")
                .font(.headline)
            Text(book.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("分类", systemImage: "folder")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    categoryChip(nil)
                    ForEach(store.categories) { cat in
                        categoryChip(cat)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func categoryChip(_ cat: BookCategory?) -> some View {
        let isSelected = book.categoryId == cat?.id
        let color = cat.map { Color(hex: $0.colorHex) } ?? Color.secondary
        return Button {
            book.categoryId = cat?.id
            store.updateBook(book)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat?.icon ?? "tray")
                    .font(.caption)
                Text(cat?.name ?? "未分类")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? color : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Read Button

    private var readButton: some View {
        Button {
            showReader = true
        } label: {
            HStack {
                Image(systemName: book.readingProgress > 0 ? "book.pages" : "book")
                Text(book.readingProgress > 0 ? "继续阅读" : "开始阅读")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Cover image

    @ViewBuilder
    private var coverImageView: some View {
        if let url = book.coverImageURL, let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            defaultCover
        }
    }

    private var defaultCover: some View {
        let colors: [Color] = [.indigo, .teal, .orange, .pink, .purple, .blue, .green]
        let color = colors[abs(book.title.hashValue) % colors.count]
        return LinearGradient(colors: [color, color.opacity(0.6)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.8))
            )
    }

    // MARK: - Helpers

    private func toggleFavorite() {
        book.isFavorite.toggle()
        store.updateBook(book)
    }
}
