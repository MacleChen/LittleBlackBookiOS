import SwiftUI

@MainActor
final class OnlineBookViewModel: ObservableObject {
    @Published var doubanBooks:      [OnlineBook] = []
    @Published var openLibraryBooks: [OnlineBook] = []
    @Published var gutenbergBooks:   [OnlineBook] = []
    @Published var searchText   = ""
    @Published var selectedTab: OnlineBook.Source = .douban
    @Published var isSearching  = false
    @Published var isLoadingId: String? = nil
    @Published var errorMessage: String? = nil
    @Published var importedIds: Set<String> = []

    // Per-source status labels shown in UI
    @Published var doubanStatus:   String? = nil
    @Published var openLibStatus:  String? = nil
    @Published var gutenbergStatus: String? = nil

    var displayedBooks: [OnlineBook] {
        switch selectedTab {
        case .douban:      return doubanBooks
        case .openLibrary: return openLibraryBooks
        case .gutenberg:   return gutenbergBooks
        }
    }

    var currentStatus: String? {
        switch selectedTab {
        case .douban:      return doubanStatus
        case .openLibrary: return openLibStatus
        case .gutenberg:   return gutenbergStatus
        }
    }

    func search() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching    = true
        errorMessage   = nil
        doubanBooks    = []
        openLibraryBooks = []
        gutenbergBooks = []
        doubanStatus   = nil
        openLibStatus  = nil
        gutenbergStatus = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.searchDouban(query: q) }
            group.addTask { await self.searchOL(query: q) }
            group.addTask { await self.searchGut(query: q) }
        }
        isSearching = false
    }

    private func searchDouban(query: String) async {
        do {
            doubanBooks = try await OnlineBookService.shared.searchDouban(query: query)
            let dl = doubanBooks.filter(\.canDownload).count
            doubanStatus = dl > 0
                ? "找到 \(doubanBooks.count) 本，\(dl) 本可下载"
                : "找到 \(doubanBooks.count) 本（版权书无免费下载，可手动导入 EPUB）"
        } catch OnlineBookService.Err.noResults {
            doubanStatus = "豆瓣未找到相关书籍"
        } catch {
            doubanStatus = "豆瓣搜索失败：\(error.localizedDescription)"
        }
    }

    private func searchOL(query: String) async {
        do {
            openLibraryBooks = try await OnlineBookService.shared.searchOpenLibrary(query: query)
            let dl = openLibraryBooks.filter(\.canDownload).count
            openLibStatus = "找到 \(openLibraryBooks.count) 本，\(dl) 本可下载"
        } catch OnlineBookService.Err.noResults {
            openLibStatus = "Open Library 未找到相关书籍"
        } catch {
            openLibStatus = "Open Library 搜索失败：\(error.localizedDescription)"
        }
    }

    private func searchGut(query: String) async {
        do {
            gutenbergBooks = try await OnlineBookService.shared.searchGutenberg(query: query)
            gutenbergStatus = "找到 \(gutenbergBooks.count) 本可下载"
        } catch OnlineBookService.Err.noResults {
            gutenbergStatus = "Gutenberg 未找到相关书籍"
        } catch {
            gutenbergStatus = "Gutenberg 搜索失败：\(error.localizedDescription)"
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
