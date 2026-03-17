import SwiftUI

@MainActor
final class OnlineBookViewModel: ObservableObject {
    @Published var openLibraryBooks: [OnlineBook] = []
    @Published var gutenbergBooks:   [OnlineBook] = []
    @Published var googleBooks:      [OnlineBook] = []
    @Published var searchText   = ""
    @Published var selectedTab: OnlineBook.Source = .googleBooks
    @Published var isSearching  = false
    @Published var isLoadingId: String? = nil
    @Published var errorMessage: String? = nil
    @Published var importedIds: Set<String> = []

    var displayedBooks: [OnlineBook] {
        switch selectedTab {
        case .googleBooks:  return googleBooks
        case .openLibrary:  return openLibraryBooks
        case .gutenberg:    return gutenbergBooks
        }
    }

    func search() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        openLibraryBooks = []
        gutenbergBooks   = []
        googleBooks      = []

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.searchGoogle(query: q) }
            group.addTask { await self.searchOL(query: q) }
            group.addTask { await self.searchGut(query: q) }
        }
        isSearching = false
    }

    private func searchGoogle(query: String) async {
        do {
            googleBooks = try await OnlineBookService.shared.searchGoogleBooks(query: query)
        } catch { /* silent — other sources may succeed */ }
    }

    private func searchOL(query: String) async {
        do {
            openLibraryBooks = try await OnlineBookService.shared.searchOpenLibrary(query: query)
        } catch { /* silent */ }
    }

    private func searchGut(query: String) async {
        do {
            gutenbergBooks = try await OnlineBookService.shared.searchGutenberg(query: query)
        } catch { /* silent */ }

        // After all searches done, show error only if everything is empty
        if googleBooks.isEmpty && openLibraryBooks.isEmpty && gutenbergBooks.isEmpty {
            errorMessage = "未找到相关书籍，请换个关键词试试"
        }
    }

    func downloadToLibrary(book: OnlineBook) async {
        guard isLoadingId == nil, book.canDownload else { return }
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
