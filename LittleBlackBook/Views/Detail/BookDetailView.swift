import SwiftUI

struct BookDetailView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @State var book: Book
    @State private var isEditing       = false
    @State private var showReader      = false
    @State private var showDeleteConfirm = false
    @State private var showNotes       = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.bottom, 24)

                    statsRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    if !book.description.isEmpty {
                        descriptionSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }

                    notesSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

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
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
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
                bottomActions
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $isEditing) {
            BookEditView(book: $book).environmentObject(store)
        }
        .fullScreenCover(isPresented: $showReader) {
            EPUBReaderView(book: $book).environmentObject(store)
        }
        .sheet(isPresented: $showNotes) {
            NotesEditorSheet(notes: $book.notes, onSave: { store.updateBook(book) })
        }
        .confirmationDialog("确认删除《\(book.title)》？",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                store.deleteBook(book)
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            coverImageView
                .frame(maxWidth: .infinity).frame(height: 280)
                .clipped().overlay(.ultraThinMaterial)

            HStack(alignment: .bottom, spacing: 16) {
                coverImageView
                    .frame(width: 110, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.title3.bold()).foregroundStyle(.primary).lineLimit(3)
                    Text(book.author)
                        .font(.subheadline).foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if book.isFavorite {
                            Label("已收藏", systemImage: "heart.fill")
                                .font(.caption).foregroundStyle(.pink)
                        }
                        if book.isFinished {
                            Label("已读完", systemImage: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
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
                value: book.isFinished ? "已完成" : (book.readingProgress > 0 ? "\(Int(book.readingProgress * 100))%" : "未读"),
                label: "阅读进度",
                icon: book.isFinished ? "checkmark.seal.fill" : "book.pages",
                tint: book.isFinished ? .green : .accentColor
            )
            Divider().frame(height: 40)
            statItem(
                value: book.lastReadDate.map { $0.formatted(.relative(presentation: .named)) } ?? "—",
                label: "上次阅读",
                icon: "clock"
            )
            Divider().frame(height: 40)
            statItem(
                value: book.finishedDate.map { $0.formatted(date: .abbreviated, time: .omitted) }
                    ?? book.addedDate.formatted(date: .abbreviated, time: .omitted),
                label: book.finishedDate != nil ? "读完日期" : "加入日期",
                icon: book.finishedDate != nil ? "flag.checkered" : "calendar"
            )
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statItem(value: String, label: String, icon: String, tint: Color = .accentColor) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint)
            Text(value).font(.system(size: 13, weight: .semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("简介", systemImage: "text.alignleft").font(.headline)
            Text(book.description)
                .font(.callout).foregroundStyle(.secondary).lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("读后感", systemImage: "pencil.line").font(.headline)
                Spacer()
                Button { showNotes = true } label: {
                    Text(book.notes.isEmpty ? "写读后感" : "编辑")
                        .font(.subheadline)
                        .foregroundStyle(.accent)
                }
            }

            if book.notes.isEmpty {
                Text("还没有读后感，点击「写读后感」记录你的感想")
                    .font(.callout)
                    .foregroundStyle(Color(.placeholderText))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(book.notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if book.notes.count > 200 {
                    Button("查看全文") { showNotes = true }
                        .font(.caption)
                        .foregroundStyle(.accent)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("分类", systemImage: "folder").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    categoryChip(nil)
                    ForEach(store.categories) { cat in categoryChip(cat) }
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

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        VStack(spacing: 10) {
            // Mark finished button — only when not yet finished
            if !book.isFinished {
                Button { markFinished() } label: {
                    HStack {
                        Image(systemName: "checkmark.seal")
                        Text("标记完成")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.green.opacity(0.4), lineWidth: 1)
                    )
                }
            }

            // Read button
            Button { showReader = true } label: {
                HStack {
                    Image(systemName: book.readingProgress > 0 ? "book.pages" : "book")
                    Text(book.isFinished ? "再次阅读" : (book.readingProgress > 0 ? "继续阅读" : "开始阅读"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Helpers

    private func toggleFavorite() {
        book.isFavorite.toggle()
        store.updateBook(book)
    }

    private func markFinished() {
        book.isFinished      = true
        book.finishedDate    = Date()
        book.readingProgress = 1.0
        book.lastReadDate    = Date()
        store.updateBook(book)
    }

    // MARK: - Cover image

    @ViewBuilder
    private var coverImageView: some View {
        if let url = book.coverImageURL, let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            defaultCover
        }
    }

    private var defaultCover: some View {
        let colors: [Color] = [.indigo, .teal, .orange, .pink, .purple, .blue, .green]
        let color = colors[abs(book.title.hashValue) % colors.count]
        return LinearGradient(colors: [color, color.opacity(0.6)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "book.closed.fill")
                .font(.system(size: 48)).foregroundStyle(.white.opacity(0.8)))
    }
}

// MARK: - Notes Editor Sheet

struct NotesEditorSheet: View {
    @Binding var notes: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                    TextEditor(text: $draft)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .padding(10)
                    if draft.isEmpty {
                        Text("写下你的读后感想…")
                            .foregroundStyle(Color(.placeholderText))
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                .padding(20)
            }
            .navigationTitle("读后感")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        notes = draft
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { draft = notes }
        }
    }
}
