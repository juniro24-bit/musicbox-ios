import SwiftUI

@main
struct MusicBoxApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var player: PlayerService
    @StateObject private var importer: ImportService

    init() {
        let lib = LibraryStore()
        let playerService = PlayerService()
        playerService.onPlayed = { [weak lib] id in
            lib?.incrementPlay(id: id)
        }
        _library = StateObject(wrappedValue: lib)
        _player = StateObject(wrappedValue: playerService)
        _importer = StateObject(wrappedValue: ImportService(library: lib))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(importer)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
        }
    }
}
