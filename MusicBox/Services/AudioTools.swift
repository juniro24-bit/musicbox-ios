import AVFoundation
import Foundation

enum AudioToolsError: LocalizedError {
    case cannotCreateSession
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateSession:
            return "이 파일은 변환할 수 없어요."
        case .exportFailed(let message):
            return "변환에 실패했어요: \(message)"
        }
    }
}

/// 오디오 길이 확인, 내보내기(자르기/컨테이너 정리), 파형 만들기. 전부 Apple 기본 프레임워크만 써요.
enum AudioTools {
    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? seconds : 0
    }

    static func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let ok = try? await asset.load(.isPlayable) else { return false }
        return ok
    }

    /// 파일에 들어 있는 제목/아티스트 태그
    static func tags(of url: URL) async -> (title: String?, artist: String?) {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return (nil, nil) }
        var title: String? = nil
        var artist: String? = nil
        let titleItems = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierTitle)
        if let item = titleItems.first {
            title = try? await item.load(.stringValue)
        }
        let artistItems = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtist)
        if let item = artistItems.first {
            artist = try? await item.load(.stringValue)
        }
        return (title, artist)
    }

    /// AVAssetExportSession 으로 파일을 내보내요. range 를 주면 그 구간만 남겨요.
    static func export(
        asset: AVAsset,
        preset: String,
        range: CMTimeRange?,
        fileType: AVFileType,
        to dest: URL
    ) async throws {
        try? FileManager.default.removeItem(at: dest)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw AudioToolsError.cannotCreateSession
        }
        session.outputURL = dest
        session.outputFileType = fileType
        if let range = range {
            session.timeRange = range
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }
        if session.status != .completed {
            try? FileManager.default.removeItem(at: dest)
            throw AudioToolsError.exportFailed(session.error?.localizedDescription ?? "알 수 없는 오류")
        }
    }

    /// 구간 자르기. 먼저 재인코딩 없이(음질 손실 없이) 시도하고, 안 되면 다시 인코딩해요.
    static func trim(src: URL, start: Double, end: Double, to dest: URL) async throws {
        let asset = AVURLAsset(url: src)
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        do {
            try await export(asset: asset, preset: AVAssetExportPresetPassthrough, range: range, fileType: .m4a, to: dest)
        } catch {
            try await export(asset: asset, preset: AVAssetExportPresetAppleM4A, range: range, fileType: .m4a, to: dest)
        }
    }

    /// 편집 화면에 그릴 파형 (0~1 로 맞춘 구간별 최대 크기)
    static func waveform(url: URL, buckets: Int = 240) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio),
              let track = tracks.first else { return [] }
        let seconds = await duration(of: url)
        guard seconds > 0, let reader = try? AVAssetReader(asset: asset) else { return [] }

        let sampleRate = 8000.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        let totalSamples = max(1, Int(seconds * sampleRate))
        let perBucket = max(1, totalSamples / buckets)
        var peaks = [Float](repeating: 0, count: buckets)
        var seen = 0

        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Int16>.size
            if count == 0 { continue }
            var samples = [Int16](repeating: 0, count: count)
            let status: OSStatus = samples.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(
                    block,
                    atOffset: 0,
                    dataLength: count * MemoryLayout<Int16>.size,
                    destination: base
                )
            }
            if status != kCMBlockBufferNoErr { continue }
            for sample in samples {
                let bucket = min(buckets - 1, seen / perBucket)
                let value = Float(abs(Int32(sample))) / 32768
                if value > peaks[bucket] { peaks[bucket] = value }
                seen += 1
            }
        }

        let loudest = peaks.max() ?? 0
        if loudest > 0 {
            peaks = peaks.map { $0 / loudest }
        }
        return peaks
    }
}
