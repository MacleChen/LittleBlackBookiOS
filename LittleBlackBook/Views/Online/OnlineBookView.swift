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

    // MARK: - Source picker

    private var sourceSegment: some View {
        Picker("来源", selection: $vm.selectedTab) {
            ForEach(OnlineBook.Source.allCases, id: \.self) { src in
                Text(src.rawValue).tag(src)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                Text("Open Library — 数百万本开放获取电子书")
                Text("Project Gutenberg — 7万+ 经典公版书（EPUB）")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
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
            AsyncImage(url: book.coverURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(.tertiarySystemFill)
                    .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
            }
            .frame(width: 48, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)

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
                        Text("\(year)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(book.format)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                    Text(book.source.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isLoading {
                ProgressView()
            } else {
                Button(action: onDownload) {
                    Image(systemName: isImported ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(isImported ? .green : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isImported)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - CaseIterable for Source picker

extension OnlineBook.Source: CaseIterable {
    static var allCases: [OnlineBook.Source] { [.openLibrary, .gutenberg] }
}
