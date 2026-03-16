import Foundation

struct BookCategory: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var icon: String      // SF Symbol name
    var colorHex: String  // hex color string
    var createdDate: Date = Date()
    var sortOrder: Int = 0

    static let defaultCategories: [BookCategory] = [
        BookCategory(name: "未分类", icon: "tray", colorHex: "#8E8E93"),
        BookCategory(name: "文学小说", icon: "books.vertical", colorHex: "#FF6B6B"),
        BookCategory(name: "科技", icon: "cpu", colorHex: "#4ECDC4"),
        BookCategory(name: "历史", icon: "scroll", colorHex: "#FFE66D"),
        BookCategory(name: "艺术设计", icon: "paintpalette", colorHex: "#A78BFA"),
    ]
}
