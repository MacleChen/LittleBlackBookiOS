import SwiftUI

struct ContentView: View {
    @StateObject private var store      = BookStore.shared
    @StateObject private var musicStore = MusicStore.shared
    @StateObject private var player     = MusicPlayer.shared
    @State private var showFullPlayer   = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryView()
                    .tabItem { Label("书库", systemImage: "books.vertical.fill") }
                    .environmentObject(store)

                MusicView()
                    .tabItem { Label("音乐", systemImage: "music.note.list") }
                    .environmentObject(musicStore)
            }
            .tint(.indigo)
            .safeAreaInset(edge: .bottom) {
                if player.currentTrack != nil {
                    MiniPlayerView(onTap: { showFullPlayer = true })
                }
            }
        }
        .sheet(isPresented: $showFullPlayer) {
            MusicPlayerView()
        }
    }
}
