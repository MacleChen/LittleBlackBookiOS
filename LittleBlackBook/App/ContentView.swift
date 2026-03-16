import SwiftUI

struct ContentView: View {
    @StateObject private var store = BookStore.shared

    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("书库", systemImage: "books.vertical.fill")
                }
                .environmentObject(store)

            CategoriesView()
                .tabItem {
                    Label("分类", systemImage: "folder.fill")
                }
                .environmentObject(store)
        }
        .tint(.indigo)
    }
}
