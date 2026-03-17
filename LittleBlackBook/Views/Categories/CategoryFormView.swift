import SwiftUI

struct CategoryFormView: View {
    enum Mode {
        case add
        case edit(name: String, icon: String, colorHex: String)
    }

    let mode: Mode
    let onSave: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedIcon: String = "folder"
    @State private var selectedColor: String = "#4ECDC4"

    private let icons = [
        "folder", "books.vertical", "book", "bookmark", "doc.text",
        "star", "heart", "flame", "bolt", "leaf",
        "globe", "cpu", "paintpalette", "music.note", "camera",
        "scroll", "graduationcap", "briefcase", "house", "person",
        "airplane", "map", "magnifyingglass", "lightbulb", "gamecontroller"
    ]

    private let colors = [
        "#FF6B6B", "#FF8E53", "#FFE66D", "#4ECDC4", "#45B7D1",
        "#2C5F8A", "#A78BFA", "#F9A8D4", "#86EFAC", "#FCD34D",
        "#6B7280", "#1F2937", "#059669", "#DC2626", "#7C3AED"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("分类名称") {
                    TextField("输入分类名称", text: $name)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedIcon == icon
                                              ? Color(hex: selectedColor)
                                              : Color(.tertiarySystemFill))
                                        .frame(height: 44)
                                    Image(systemName: icon)
                                        .font(.system(size: 20))
                                        .foregroundStyle(selectedIcon == icon ? .white : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(colors, id: \.self) { hex in
                            Button {
                                selectedColor = hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 36, height: 36)
                                    if selectedColor == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // Preview
                Section("预览") {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: selectedColor).gradient)
                                .frame(width: 42, height: 42)
                            Image(systemName: selectedIcon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        Text(name.isEmpty ? "分类名称" : name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(mode.isAdd ? "新建分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        if case .edit(let n, let i, let c) = mode {
            name          = n
            selectedIcon  = i
            selectedColor = c
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, selectedIcon, selectedColor)
        dismiss()
    }
}

extension CategoryFormView.Mode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
    var title: String { isAdd ? "新建分类" : "编辑分类" }
}
