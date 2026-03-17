import SwiftUI

@main
struct LittleBlackBookApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                showSplash = false
                            }
                        }
                    }
            } else {
                ContentView()
                    .transition(.opacity)
            }
        }
    }
}
