import SwiftUI

struct ContentView: View {
    @StateObject private var store      = BookStore.shared
    @StateObject private var musicStore = MusicStore.shared
    @StateObject private var player     = MusicPlayer.shared
    @State private var showFullPlayer   = false

    var body: some View {
        TabView {
            LibraryView()
                .environmentObject(store)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayerBar }
                .tabItem { Label("书库", systemImage: "books.vertical.fill") }

            MusicView()
                .environmentObject(musicStore)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayerBar }
                .tabItem { Label("音乐", systemImage: "music.note.list") }
        }
        .tint(.indigo)
        .sheet(isPresented: $showFullPlayer) {
            MusicPlayerView()
        }
    }

    @ViewBuilder
    private var miniPlayerBar: some View {
        if player.currentTrack != nil {
            MiniPlayerView(onTap: { showFullPlayer = true })
        }
    }
}
