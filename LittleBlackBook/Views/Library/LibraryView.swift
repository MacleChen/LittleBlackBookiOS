import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var store: BookStore
    @StateObject private var vm = LibraryViewModel()
    @State private var showImportPicker = false
    @State private var readerBook: Book? = nil   // tap  → direct reading
    @State private var detailBook: Book? = nil   // context menu → detail sheet

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if vm.filteredBooks.isEmpty { emptyState } else { bookGrid }
            }
            .navigationTitle("我的书库")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .searchable(text: $vm.searchText, prompt: "搜索书名或作者")
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top) { categoryFilterBar }
        }
        // Tap → open reader directly
        .fullScreenCover(item: $readerBook) { book in
            EPUBReaderView(book: Binding(
                get: { store.books.first(where: { $0.id == book.id }) ?? book },
                set: { store.updateBook($0) }
            ))
            .environmentObject(store)
        }
        // Context menu 详情 → detail sheet
        .sheet(item: $detailBook) { book in
            BookDetailView(book: book)
                .environmentObject(store)
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): urls.forEach { vm.importBook(from: $0) }
            case .failure(let error): vm.importError = error.localizedDescription
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
    }

    // MARK: - Subviews

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(vm.filteredBooks) { book in
                    BookCardView(
                        book: book,
                        onDetail:   { detailBook = book },
                        onFavorite: { vm.toggleFavorite(book) },
                        onDelete:   { vm.deleteBook(book) }
                    )
                    .onTapGesture { readerBook = book }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无书籍", systemImage: "books.vertical")
        } description: {
            Text("点击右上角 + 按钮导入 EPUB 电子书")
        } actions: {
            Button { showImportPicker = true } label: {
                Label("导入书籍", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterChip(title: "全部", icon: "square.grid.2x2",
                           isSelected: vm.selectedCategory == nil,
                           color: Color.accentColor) { vm.selectedCategory = nil }
                ForEach(store.categories) { cat in
                    FilterChip(title: cat.name, icon: cat.icon,
                               isSelected: vm.selectedCategory?.id == cat.id,
                               color: cat.colorHex.asColor) {
                        vm.selectedCategory = (vm.selectedCategory?.id == cat.id) ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(LibraryViewModel.SortOption.allCases, id: \.self) { opt in
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
}

// MARK: - Filter Chip

struct FilterChip: View {
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
