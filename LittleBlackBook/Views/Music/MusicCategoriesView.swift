import SwiftUI

struct MusicCategoriesView: View {
    @EnvironmentObject var musicStore: MusicStore
    @State private var showAddSheet = false
    @State private var editingCategory: MusicCategory? = nil
    @State private var deletingCategory: MusicCategory? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(musicStore.categories) { cat in
                    MusicCategoryRow(category: cat, trackCount: musicStore.trackCount(for: cat))
                        .contentShape(Rectangle())
                        .onTapGesture { editingCategory = cat }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deletingCategory = cat
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                editingCategory = cat
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                }
                .onMove { source, destination in
                    var cats = musicStore.categories
                    cats.move(fromOffsets: source, toOffset: destination)
                    for (i, var c) in cats.enumerated() {
                        if c.sortOrder != i {
                            c.sortOrder = i
                            musicStore.updateCategory(c)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("音乐分类")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 22))
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .overlay {
                if musicStore.categories.isEmpty {
                    ContentUnavailableView(
                        "暂无分类",
                        systemImage: "folder.badge.plus",
                        description: Text("点击 + 创建新分类")
                    )
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CategoryFormView(mode: .add) { name, icon, color in
                let cat = MusicCategory(name: name, icon: icon, colorHex: color,
                                        sortOrder: musicStore.categories.count)
                musicStore.addCategory(cat)
            }
        }
        .sheet(item: $editingCategory) { cat in
            CategoryFormView(mode: .edit(name: cat.name, icon: cat.icon, colorHex: cat.colorHex)) { name, icon, color in
                var updated = cat
                updated.name = name
                updated.icon = icon
                updated.colorHex = color
                musicStore.updateCategory(updated)
            }
        }
        .confirmationDialog(
            "确认删除「\(deletingCategory?.name ?? "")」？\n该分类下的歌曲将移至未分类。",
            isPresented: Binding(
                get: { deletingCategory != nil },
                set: { if !$0 { deletingCategory = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let cat = deletingCategory { musicStore.deleteCategory(cat) }
                deletingCategory = nil
            }
            Button("取消", role: .cancel) { deletingCategory = nil }
        }
    }
}

// MARK: - Music Category Row

struct MusicCategoryRow: View {
    let category: MusicCategory
    let trackCount: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: category.colorHex).gradient)
                    .frame(width: 42, height: 42)
                Image(systemName: category.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.system(size: 16, weight: .medium))
                Text("\(trackCount) 首")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
