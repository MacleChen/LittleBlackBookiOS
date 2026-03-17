import Foundation

struct MusicCategory: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var icon: String       // SF Symbol name
    var colorHex: String
    var createdDate: Date = Date()
    var sortOrder: Int = 0

    static let defaultCategories: [MusicCategory] = [
        MusicCategory(name: "未分类",  icon: "music.note",      colorHex: "#8E8E93"),
        MusicCategory(name: "流行",    icon: "music.mic",        colorHex: "#FF6B6B"),
        MusicCategory(name: "古典",    icon: "pianokeys",        colorHex: "#4ECDC4"),
        MusicCategory(name: "摇滚",    icon: "guitars",          colorHex: "#FFE66D"),
        MusicCategory(name: "轻音乐",  icon: "cloud",            colorHex: "#A78BFA"),
        MusicCategory(name: "国风",    icon: "music.quarternote.3", colorHex: "#F4A261"),
    ]
}
