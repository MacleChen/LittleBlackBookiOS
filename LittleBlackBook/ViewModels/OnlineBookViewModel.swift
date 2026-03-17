import SwiftUI

@MainActor
final class OnlineBookViewModel: ObservableObject {
    @Published var openLibraryBooks: [OnlineBook] = []
    @Published var gutenbergBooks:   [OnlineBook] = []
    @Published var searchText  = ""
    @Published var selectedTab: OnlineBook.Source = .openLibrary
    @Published var isSearching  = false
    @Published var isLoadingId: String? = nil
    @Published var errorMessage: String? = nil
    @Published var importedIds: Set<String> = []

    var displayedBooks: [OnlineBook] {
        selectedTab == .openLibrary ? openLibraryBooks : gutenbergBooks
    }

    func search() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        openLibraryBooks = []
        gutenbergBooks   = []
        async let olSearch  = searchOL(query: q)
        async let gutSearch = searchGut(query: q)
        _ = await (olSearch, gutSearch)
        isSearching = false
    }

    private func searchOL(query: String) async {
        do {
            openLibraryBooks = try await OnlineBookService.shared.searchOpenLibrary(query: query)
        } catch {
            if openLibraryBooks.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func searchGut(query: String) async {
        do {
            gutenbergBooks = try await OnlineBookService.shared.searchGutenberg(query: query)
        } catch {
            if gutenbergBooks.isEmpty && openLibraryBooks.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func downloadToLibrary(book: OnlineBook) async {
        guard isLoadingId == nil else { return }
        isLoadingId = book.id
        errorMessage = nil
        do {
            let tmpURL = try await OnlineBookService.shared.downloadBook(book: book)
            try await BookStore.shared.addBook(from: tmpURL)
            try? FileManager.default.removeItem(at: tmpURL)
            importedIds.insert(book.id)
        } catch {
            errorMessage = "下载失败：\(error.localizedDescription)"
        }
        isLoadingId = nil
    }
}
