import SwiftUI
import Combine
import UniformTypeIdentifiers

class LibraryViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedCategory: BookCategory? = nil
    @Published var selectedBook: Book? = nil
    @Published var isImporting: Bool = false
    @Published var isShowingDetail: Bool = false
    @Published var importError: String? = nil
    @Published var sortOption: SortOption = .dateAdded

    enum SortOption: String, CaseIterable {
        case dateAdded  = "添加时间"
        case title      = "书名"
        case author     = "作者"
        case lastRead   = "最近阅读"
    }

    private let store: BookStore
    private var cancellables = Set<AnyCancellable>()

    init(store: BookStore = .shared) {
        self.store = store
    }

    var filteredBooks: [Book] {
        var result = store.books

        if let cat = selectedCategory {
            result = result.filter { $0.categoryId == cat.id }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                $0.author.lowercased().contains(q)
            }
        }

        switch sortOption {
        case .dateAdded: result.sort { $0.addedDate > $1.addedDate }
        case .title:     result.sort { $0.title < $1.title }
        case .author:    result.sort { $0.author < $1.author }
        case .lastRead:
            result.sort {
                ($0.lastReadDate ?? .distantPast) > ($1.lastReadDate ?? .distantPast)
            }
        }

        return result
    }

    func importBook(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            _ = try store.addBook(from: url, category: selectedCategory)
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    func deleteBook(_ book: Book) {
        store.deleteBook(book)
    }

    func toggleFavorite(_ book: Book) {
        var updated = book
        updated.isFavorite.toggle()
        store.updateBook(updated)
    }

    func category(for book: Book) -> BookCategory? {
        guard let cid = book.categoryId else { return nil }
        return store.categories.first { $0.id == cid }
    }
}
