import Foundation
import YouTubeKit

enum ImportError: LocalizedError {
    case invalidLink
    case playlistOnly
    case duplicate
    case noAudio
    case http(Int)
    case emptyFile
    case unplayable

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            return "유튜브 링크를 찾지 못했어요. 곡 링크를 통째로 붙여넣어 주세요."
        case .playlistOnly:
            return "재생목록 링크는 아직 지원하지 않아요. 곡 하나의 링크를 붙여넣어 주세요."
        case .duplicate:
            return "이미 가져온 곡이에요."
        case .noAudio:
            return "받을 수 있는 오디오를 찾지 못했어요."
        case .http(let code):
            return "다운로드가 거부됐어요 (코드 \(code))."
        case .emptyFile:
            return "받은 파일이 비어 있어요."
        case .unplayable:
            return "받은 파일을 재생할 수 없어요."
        }
    }
}

struct VideoMeta {
    let title: String
    let author: String?
}

/// 링크에서 영상 ID 뽑기
enum YouTubeLink {
    static func videoID(from text: String) -> String? {
        let pattern = #"(?:youtu\.be/|youtube(?:-nocookie)?\.com/(?:watch\?(?:[^\s#]*&)?v=|shorts/|live/|embed/|v/))([A-Za-z0-9_-]{11})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let idRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[idRange])
    }

    static func looksLikePlaylist(_ text: String) -> Bool {
        text.contains("list=") && text.contains("youtube")
    }
}

/// 유튜브에서 오디오 주소, 제목, 커버를 가져오는 부분.
/// 서버 없이 폰 안에서만 동작하도록 YouTubeKit 을 로컬 추출(.local)로만 써요.
enum YouTubeResolver {
    static func audioURL(videoID: String) async throws -> URL {
        let video = YouTube(videoID: videoID, methods: [.local])
        let streams = try await video.streams
        let audioOnly = streams.filterAudioOnly()
        let m4a = audioOnly.filter { $0.fileExtension == .m4a }
        let candidates = [m4a.highestAudioBitrateStream(), audioOnly.highestAudioBitrateStream()]
        guard let url = candidates.compactMap({ $0 }).first?.url else {
            throw ImportError.noAudio
        }
        return url
    }

    private struct OEmbed: Decodable {
        let title: String?
        let author_name: String?
    }

    /// 제목과 채널 이름 (유튜브 공식 oEmbed 주소, 로그인 필요 없음)
    static func meta(videoID: String) async -> VideoMeta? {
        guard var comps = URLComponents(string: "https://www.youtube.com/oembed") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoID)"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(OEmbed.self, from: data)
            guard let title = decoded.title, !title.isEmpty else { return nil }
            return VideoMeta(title: title, author: decoded.author_name)
        } catch {
            return nil
        }
    }

    /// 썸네일 (큰 것부터 시도)
    static func coverData(videoID: String) async -> Data? {
        for name in ["maxresdefault", "mqdefault"] {
            guard let url = URL(string: "https://i.ytimg.com/vi/\(videoID)/\(name).jpg") else { continue }
            if let (data, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               data.count > 2000 {
                return data
            }
        }
        return nil
    }
}
