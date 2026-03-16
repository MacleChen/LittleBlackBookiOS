import SwiftUI

class CategoriesViewModel: ObservableObject {
    private let store: BookStore

    init(store: BookStore = .shared) {
        self.store = store
    }

    var categories: [BookCategory] { store.categories }

    func addCategory(name: String, icon: String, colorHex: String) {
        let cat = BookCategory(name: name, icon: icon, colorHex: colorHex,
                               sortOrder: store.categories.count)
        store.addCategory(cat)
    }

    func updateCategory(_ cat: BookCategory) {
        store.updateCategory(cat)
    }

    func deleteCategory(_ cat: BookCategory) {
        store.deleteCategory(cat)
    }

    func bookCount(for cat: BookCategory) -> Int {
        store.bookCount(for: cat)
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        var cats = store.categories
        cats.move(fromOffsets: source, toOffset: destination)
        for (i, var c) in cats.enumerated() {
            c.sortOrder = i
            store.updateCategory(c)
        }
    }
}
