import Foundation

/// 앱이 쓰는 폴더 위치. 곡은 Documents 안에 저장돼서 "파일" 앱에서도 보여요.
enum Paths {
    static let docs: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let audio: URL = docs.appendingPathComponent("Audio", isDirectory: true)
    static let covers: URL = docs.appendingPathComponent("Covers", isDirectory: true)
    static let library: URL = docs.appendingPathComponent("library.json")

    static func prepare() {
        for dir in [audio, covers] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func audioURL(_ track: Track) -> URL {
        audio.appendingPathComponent(track.fileName)
    }

    static func coverURL(_ track: Track) -> URL? {
        guard let name = track.coverFileName else { return nil }
        return covers.appendingPathComponent(name)
    }

    static func tempURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
    }
}
