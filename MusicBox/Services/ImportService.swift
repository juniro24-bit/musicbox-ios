import AVFoundation
import Foundation

/// 청크로 나눠 받기 (유튜브 서버가 한 번에 크게 받는 걸 느리게 만드는 경우를 피해요)
enum Downloader {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func download(from url: URL, to dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        let chunk: Int64 = 8 * 1024 * 1024
        var offset: Int64 = 0
        var total: Int64 = 0

        while true {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("bytes=\(offset)-\(offset + chunk - 1)", forHTTPHeaderField: "Range")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ImportError.http(0) }

            // 서버가 Range 를 무시하고 통째로 준 경우
            if http.statusCode == 200 && offset == 0 {
                try handle.write(contentsOf: data)
                progress(1)
                return
            }
            guard http.statusCode == 206 else { throw ImportError.http(http.statusCode) }

            try handle.write(contentsOf: data)
            offset += Int64(data.count)

            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let slash = range.lastIndex(of: "/"),
               let size = Int64(range[range.index(after: slash)...]) {
                total = size
            }
            if total > 0 { progress(min(1, Double(offset) / Double(total))) }

            if data.isEmpty { break }
            if total > 0 && offset >= total { break }
            if total == 0 && Int64(data.count) < chunk { break }
        }
    }
}

/// 가져오기 작업 하나 (화면에 진행 상황을 보여줘요)
@MainActor
final class ImportJob: ObservableObject, Identifiable {
    enum State {
        case waiting, resolving, downloading, processing, done, failed
    }

    let id = UUID()
    let input: String
    @Published var state: State = .waiting
    @Published var progress: Double = 0
    @Published var title: String = ""
    @Published var message: String = ""
    @Published var trackID: String?

    init(input: String) {
        self.input = input
    }

    var isActive: Bool {
        switch state {
        case .done, .failed: return false
        default: return true
        }
    }

    func fail(_ text: String) {
        message = text
        state = .failed
    }
}

@MainActor
final class ImportService: ObservableObject {
    @Published private(set) var jobs: [ImportJob] = []
    private let library: LibraryStore

    init(library: LibraryStore) {
        self.library = library
    }

    func dismiss(_ job: ImportJob) {
        jobs.removeAll { $0.id == job.id }
    }

    // MARK: 유튜브 링크로 가져오기

    func start(link: String) {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let job = ImportJob(input: text)
        jobs.insert(job, at: 0)
        Task { await runYouTube(job) }
    }

    private func runYouTube(_ job: ImportJob) async {
        var created: [URL] = []
        let raw = Paths.tempURL(ext: "m4a")
        defer { try? FileManager.default.removeItem(at: raw) }

        do {
            guard let videoID = YouTubeLink.videoID(from: job.input) else {
                throw YouTubeLink.looksLikePlaylist(job.input) ? ImportError.playlistOnly : ImportError.invalidLink
            }
            let canonical = "https://www.youtube.com/watch?v=\(videoID)"
            if library.tracks.contains(where: { $0.sourceURL == canonical }) {
                throw ImportError.duplicate
            }

            job.state = .resolving
            job.title = "정보를 확인하는 중…"
            async let metaFuture = YouTubeResolver.meta(videoID: videoID)
            let audioURL = try await YouTubeResolver.audioURL(videoID: videoID)
            let meta = await metaFuture
            job.title = meta?.title ?? "제목 없음"

            job.state = .downloading
            try await Downloader.download(from: audioURL, to: raw) { value in
                Task { @MainActor in job.progress = value }
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: raw.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            if size < 1000 { throw ImportError.emptyFile }

            job.state = .processing
            let trackID = Track.newID()
            let fileName = trackID + ".m4a"
            let finalURL = Paths.audio.appendingPathComponent(fileName)
            created.append(finalURL)

            // 유튜브의 조각난 m4a 를 일반 m4a 로 정리 (실패하면 받은 그대로 사용)
            do {
                try await AudioTools.export(
                    asset: AVURLAsset(url: raw),
                    preset: AVAssetExportPresetPassthrough,
                    range: nil,
                    fileType: .m4a,
                    to: finalURL
                )
            } catch {
                try? FileManager.default.removeItem(at: finalURL)
                try FileManager.default.copyItem(at: raw, to: finalURL)
            }

            guard await AudioTools.isPlayable(finalURL) else { throw ImportError.unplayable }
            let duration = await AudioTools.duration(of: finalURL)
            guard duration > 0 else { throw ImportError.unplayable }

            var coverName: String? = nil
            if let data = await YouTubeResolver.coverData(videoID: videoID),
               let jpeg = ImageTools.squareJPEG(from: data) {
                let name = trackID + ".jpg"
                let coverURL = Paths.covers.appendingPathComponent(name)
                do {
                    try jpeg.write(to: coverURL)
                    coverName = name
                    created.append(coverURL)
                } catch {
                    coverName = nil
                }
            }

            let artist = (meta?.author ?? "").replacingOccurrences(of: " - Topic", with: "")
            let track = Track(
                id: trackID,
                title: meta?.title ?? "제목 없음",
                artist: artist,
                duration: duration,
                fileName: fileName,
                coverFileName: coverName,
                sourceURL: canonical
            )
            library.add(track)
            job.trackID = trackID
            job.progress = 1
            job.state = .done
        } catch {
            for url in created { try? FileManager.default.removeItem(at: url) }
            job.fail(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        if let known = error as? ImportError, let text = known.errorDescription {
            return text
        }
        if error is URLError {
            return "인터넷에 연결할 수 없거나 연결이 끊겼어요. 연결을 확인하고 다시 시도해 주세요."
        }
        return "가져오지 못했어요. 유튜브가 방식을 바꿨을 수 있어요. 그럴 땐 앱을 다시 빌드해서 업데이트해야 해요.\n(\(error.localizedDescription))"
    }

    // MARK: 내 파일에서 올리기

    func importFiles(_ urls: [URL]) {
        for url in urls {
            let job = ImportJob(input: url.lastPathComponent)
            job.title = url.deletingPathExtension().lastPathComponent
            jobs.insert(job, at: 0)
            Task { await runFile(job, url: url) }
        }
    }

    private func runFile(_ job: ImportJob, url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        job.state = .processing
        job.progress = 1

        let trackID = Track.newID()
        let ext = url.pathExtension.lowercased()
        let fileName = trackID + "." + (ext.isEmpty ? "m4a" : ext)
        let dest = Paths.audio.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: url, to: dest)
            guard await AudioTools.isPlayable(dest) else {
                try? FileManager.default.removeItem(at: dest)
                throw ImportError.unplayable
            }
            let duration = await AudioTools.duration(of: dest)
            guard duration > 0 else {
                try? FileManager.default.removeItem(at: dest)
                throw ImportError.unplayable
            }
            let tags = await AudioTools.tags(of: dest)
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            let title = (tags.title?.isEmpty == false ? tags.title : nil) ?? fallbackTitle
            let track = Track(
                id: trackID,
                title: title,
                artist: tags.artist ?? "",
                duration: duration,
                fileName: fileName,
                coverFileName: nil,
                sourceURL: nil
            )
            library.add(track)
            job.title = title
            job.trackID = trackID
            job.state = .done
        } catch {
            job.fail(Self.describe(error))
        }
    }
}
