import SwiftUI

struct ContentView: View {
    @State private var tab: AppTab = .library
    @State private var showPlayer = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .library:
                    LibraryView(goImport: { tab = .add })
                case .add:
                    ImportView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            MiniPlayerView(onOpen: { showPlayer = true })
            TabBar(tab: $tab)
        }
        .appScreen()
        .sheet(isPresented: $showPlayer) {
            NowPlayingView()
        }
    }
}
