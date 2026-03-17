import SwiftUI

struct OnlineBookView: View {
    @StateObject private var vm = OnlineBookViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isSearching {
                    ProgressView("搜索中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.displayedBooks.isEmpty && !vm.searchText.isEmpty {
                    emptyState
                } else if vm.displayedBooks.isEmpty {
                    placeholderState
                } else {
                    bookList
                }
            }
            .navigationTitle("在线书库")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $vm.searchText, prompt: "搜索书名、作者")
            .onSubmit(of: .search) { Task { await vm.search() } }
            .safeAreaInset(edge: .top) { sourceSegment }
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

    // MARK: - Source segment

    private var sourceSegment: some View {
        VStack(spacing: 0) {
            Picker("来源", selection: $vm.selectedTab) {
                ForEach(OnlineBook.Source.allCases, id: \.self) { src in
                    Text(src.rawValue).tag(src)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let status = vm.currentStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer().frame(height: 8)
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Book List

    private var bookList: some View {
        List(vm.displayedBooks) { book in
            OnlineBookRow(
                book: book,
                isLoading: vm.isLoadingId == book.id,
                isImported: vm.importedIds.contains(book.id),
                onDownload: { Task { await vm.downloadToLibrary(book: book) } }
            )
            .listRowBackground(Color(.secondarySystemGroupedBackground))
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView.search(text: vm.searchText)
    }

    private var placeholderState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("搜索书名或作者")
                .font(.headline)
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Label("豆瓣图书 — 中文书籍全覆盖（含当代小说）", systemImage: "globe")
                Label("Open Library — 英文开放书籍 + 中文档案馆（EPUB）", systemImage: "archivebox")
                Label("Gutenberg — 7万+ 经典公版书（EPUB）", systemImage: "book.pages")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - OnlineBookRow

struct OnlineBookRow: View {
    let book: OnlineBook
    let isLoading: Bool
    let isImported: Bool
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Cover
            AsyncImage(url: book.coverURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(.tertiarySystemFill)
                    .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
            }
            .frame(width: 48, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(2)
                if !book.authors.isEmpty {
                    Text(book.authorText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let year = book.year {
                        Text(String(year))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if book.format != "-" {
                        Text(book.format)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    Text(book.source.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Action
            if isLoading {
                ProgressView()
            } else if isImported {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green)
            } else if book.canDownload {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Text("预览")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Source CaseIterable

extension OnlineBook.Source: CaseIterable {
    static var allCases: [OnlineBook.Source] { [.douban, .openLibrary, .gutenberg] }
}
