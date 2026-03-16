import SwiftUI

struct CategoriesView: View {
    @EnvironmentObject var store: BookStore
    @StateObject private var vm = CategoriesViewModel()
    @State private var showAddSheet = false
    @State private var editingCategory: BookCategory? = nil
    @State private var deletingCategory: BookCategory? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.categories) { cat in
                    CategoryRow(category: cat, bookCount: vm.bookCount(for: cat))
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
                .onMove { vm.moveCategory(from: $0, to: $1) }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("书籍分类")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
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
                if vm.categories.isEmpty {
                    ContentUnavailableView(
                        "暂无分类",
                        systemImage: "folder.badge.plus",
                        description: Text("点击 + 创建新分类")
                    )
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CategoryFormView(mode: .add, onSave: { name, icon, color in
                vm.addCategory(name: name, icon: icon, colorHex: color)
            })
        }
        .sheet(item: $editingCategory) { cat in
            CategoryFormView(mode: .edit(cat), onSave: { name, icon, color in
                var updated = cat
                updated.name = name
                updated.icon = icon
                updated.colorHex = color
                vm.updateCategory(updated)
            })
        }
        .confirmationDialog(
            "确认删除「\(deletingCategory?.name ?? "")」？\n该分类下的书籍将移至未分类。",
            isPresented: Binding(
                get: { deletingCategory != nil },
                set: { if !$0 { deletingCategory = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let cat = deletingCategory { vm.deleteCategory(cat) }
                deletingCategory = nil
            }
            Button("取消", role: .cancel) { deletingCategory = nil }
        }
    }
}

// MARK: - Category Row

struct CategoryRow: View {
    let category: BookCategory
    let bookCount: Int

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
                Text("\(bookCount) 本")
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
