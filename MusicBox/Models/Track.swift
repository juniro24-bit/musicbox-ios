import Foundation

/// 라이브러리에 들어 있는 곡 하나. library.json 에 그대로 저장돼요.
struct Track: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var title: String
    var artist: String
    var duration: Double
    /// Documents/Audio 안의 파일 이름
    var fileName: String
    /// Documents/Covers 안의 파일 이름
    var coverFileName: String?
    var sourceURL: String?
    var favorite: Bool = false
    var playCount: Int = 0
    var createdAt: Date = Date()

    static func newID() -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(raw.prefix(12))
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    let x = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, x) }
    return String(format: "%d:%02d", m, x)
}

func formatPrecise(_ seconds: Double) -> String {
    let s = max(0, seconds)
    let m = Int(s) / 60
    let rest = s - Double(m * 60)
    return String(format: "%d:%04.1f", m, rest)
}
