import SwiftUI

struct BookEditView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @Binding var book: Book

    @State private var title: String = ""
    @State private var author: String = ""
    @State private var description: String = ""
    @State private var tags: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    LabeledContent {
                        TextField("书名", text: $title)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text("书名")
                    }
                    LabeledContent {
                        TextField("作者", text: $author)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text("作者")
                    }
                }

                Section("简介") {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                }

                Section("标签（逗号分隔）") {
                    TextField("如：科幻, 经典", text: $tags)
                }
            }
            .navigationTitle("编辑书籍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        title       = book.title
        author      = book.author
        description = book.description
        tags        = book.tags.joined(separator: ", ")
    }

    private func save() {
        book.title       = title.trimmingCharacters(in: .whitespaces).isEmpty ? book.title : title.trimmingCharacters(in: .whitespaces)
        book.author      = author.trimmingCharacters(in: .whitespaces).isEmpty ? book.author : author.trimmingCharacters(in: .whitespaces)
        book.description = description
        book.tags        = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        store.updateBook(book)
        dismiss()
    }
}
