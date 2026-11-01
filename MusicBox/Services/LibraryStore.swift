import Foundation

/// 곡 목록 저장소. Documents/library.json 하나에 목록을 저장해요.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []

    init() {
        Paths.prepare()
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Paths.library),
              let list = try? JSONDecoder().decode([Track].self, from: data) else { return }
        tracks = list
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: Paths.library, options: .atomic)
        } catch {
            print("라이브러리 저장 실패: \(error)")
        }
    }

    func track(id: String) -> Track? {
        tracks.first { $0.id == id }
    }

    func add(_ track: Track) {
        tracks.insert(track, at: 0)
        save()
    }

    func update(_ track: Track) {
        guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[i] = track
        save()
    }

    func toggleFavorite(id: String) -> Track? {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return nil }
        tracks[i].favorite.toggle()
        save()
        return tracks[i]
    }

    func incrementPlay(id: String) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].playCount += 1
        save()
    }

    func delete(_ track: Track) {
        try? FileManager.default.removeItem(at: Paths.audioURL(track))
        if let cover = Paths.coverURL(track) {
            try? FileManager.default.removeItem(at: cover)
            CoverCache.remove(name: track.coverFileName)
        }
        tracks.removeAll { $0.id == track.id }
        save()
    }
}
