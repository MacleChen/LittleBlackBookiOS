import Foundation
import Combine

class BookStore: ObservableObject {
    static let shared = BookStore()

    @Published var books: [Book] = []
    @Published var categories: [BookCategory] = []

    private let booksKey = "lbb_books"
    private let categoriesKey = "lbb_categories"

    private init() {
        createDirectories()
        load()
        if categories.isEmpty {
            categories = BookCategory.defaultCategories
            saveCategories()
        }
    }

    // MARK: - Directories

    private func createDirectories() {
        let fm = FileManager.default
        let base = fm.documentsDirectory
        [base.appendingPathComponent("Books"),
         base.appendingPathComponent("Covers")].forEach {
            try? fm.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    // MARK: - Load / Save

    private func load() {
        if let data = UserDefaults.standard.data(forKey: booksKey),
           let decoded = try? JSONDecoder().decode([Book].self, from: data) {
            books = decoded
        }
        if let data = UserDefaults.standard.data(forKey: categoriesKey),
           let decoded = try? JSONDecoder().decode([BookCategory].self, from: data) {
            categories = decoded
        }
    }

    private func saveBooks() {
        if let data = try? JSONEncoder().encode(books) {
            UserDefaults.standard.set(data, forKey: booksKey)
        }
    }

    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: categoriesKey)
        }
    }

    // MARK: - Book CRUD

    @discardableResult
    func addBook(from sourceURL: URL, category: BookCategory? = nil) async throws -> Book {
        let fm = FileManager.default
        let destDir = fm.documentsDirectory.appendingPathComponent("Books")
        var destName = sourceURL.lastPathComponent
        var destURL = destDir.appendingPathComponent(destName)

        // avoid name collision
        var counter = 1
        while fm.fileExists(atPath: destURL.path) {
            let base = sourceURL.deletingPathExtension().lastPathComponent
            let ext  = sourceURL.pathExtension
            destName = "\(base)_\(counter).\(ext)"
            destURL  = destDir.appendingPathComponent(destName)
            counter += 1
        }

        try fm.copyItem(at: sourceURL, to: destURL)

        // Only use Readium parser for EPUB; other formats fall back to filename
        let ext = destURL.pathExtension.lowercased()
        let meta = (ext == "epub")
            ? await EPUBMetadataParser.parse(url: destURL)
            : EPUBMetadata(
                title: destURL.deletingPathExtension().lastPathComponent,
                author: "未知作者",
                description: "",
                coverImage: nil
              )

        // Save cover
        var coverName: String? = nil
        if let img = meta.coverImage, let jpeg = img.jpegData(compressionQuality: 0.85) {
            let name = UUID().uuidString + ".jpg"
            let coverURL = fm.documentsDirectory.appendingPathComponent("Covers").appendingPathComponent(name)
            try? jpeg.write(to: coverURL)
            coverName = name
        }

        let book = Book(
            title: meta.title,
            author: meta.author,
            description: meta.description,
            categoryId: category?.id,
            fileName: destName,
            coverImageName: coverName
        )

        await MainActor.run {
            books.append(book)
            saveBooks()
        }
        return book
    }

    func updateBook(_ book: Book) {
        if let idx = books.firstIndex(where: { $0.id == book.id }) {
            books[idx] = book
            saveBooks()
        }
    }

    func deleteBook(_ book: Book) {
        try? FileManager.default.removeItem(at: book.fileURL)
        if let name = book.coverImageName {
            let coverURL = FileManager.default.documentsDirectory
                .appendingPathComponent("Covers").appendingPathComponent(name)
            try? FileManager.default.removeItem(at: coverURL)
        }
        books.removeAll { $0.id == book.id }
        saveBooks()
    }

    func books(in category: BookCategory?) -> [Book] {
        guard let cat = category else { return books }
        return books.filter { $0.categoryId == cat.id }
    }

    // MARK: - Category CRUD

    func addCategory(_ category: BookCategory) {
        categories.append(category)
        saveCategories()
    }

    func updateCategory(_ category: BookCategory) {
        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
            categories[idx] = category
            saveCategories()
        }
    }

    func deleteCategory(_ category: BookCategory) {
        // move books to "uncategorized" (nil)
        for i in books.indices where books[i].categoryId == category.id {
            books[i].categoryId = nil
        }
        saveBooks()
        categories.removeAll { $0.id == category.id }
        saveCategories()
    }

    func bookCount(for category: BookCategory) -> Int {
        books.filter { $0.categoryId == category.id }.count
    }
}
