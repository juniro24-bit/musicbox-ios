import AVFoundation
import SwiftUI

/// 편집 화면에서 구간을 들어 보는 별도 플레이어 (메인 재생과 따로 동작해요)
@MainActor
final class PreviewPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0

    private var player: AVPlayer?
    private var timeToken: Any?
    private var endObserver: NSObjectProtocol?

    func toggle(url: URL, start: Double, end: Double) {
        if isPlaying {
            stop()
            return
        }
        let item = AVPlayerItem(url: url)
        item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer

        timeToken = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                if seconds.isFinite { self?.position = seconds }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }

        try? AVAudioSession.sharedInstance().setActive(true)
        isPlaying = true
        position = start
        Task {
            _ = await avPlayer.seek(
                to: CMTime(seconds: start, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            avPlayer.play()
        }
    }

    func stop() {
        if let token = timeToken {
            player?.removeTimeObserver(token)
            timeToken = nil
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
    }
}

/// 파형 위에서 남길 구간을 손잡이로 고르는 부분
struct WaveformSelector: View {
    let peaks: [Float]
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    var playhead: Double?

    @State private var active: Int?
    private let minLength = 0.5

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            Canvas { ctx, size in
                guard duration > 0 else { return }
                let xs = CGFloat(start / duration) * size.width
                let xe = CGFloat(end / duration) * size.width

                ctx.fill(
                    Path(CGRect(x: xs, y: 0, width: max(0, xe - xs), height: size.height)),
                    with: .color(Theme.amber.opacity(0.10))
                )

                if peaks.isEmpty {
                    ctx.fill(
                        Path(CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2)),
                        with: .color(Theme.dim)
                    )
                } else {
                    let n = peaks.count
                    let barWidth = size.width / CGFloat(n)
                    for i in 0..<n {
                        let h = max(3, CGFloat(peaks[i]) * size.height * 0.84)
                        let x = CGFloat(i) * barWidth
                        let mid = x + barWidth / 2
                        let inside = mid >= xs && mid <= xe
                        let rect = CGRect(x: x + 0.5, y: (size.height - h) / 2, width: max(1, barWidth - 1), height: h)
                        ctx.fill(
                            Path(roundedRect: rect, cornerRadius: 1),
                            with: .color(inside ? Theme.amber : Theme.dim)
                        )
                    }
                }

                if let head = playhead, head >= start, head <= end {
                    let x = CGFloat(head / duration) * size.width
                    ctx.fill(
                        Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)),
                        with: .color(Theme.heart)
                    )
                }

                for x in [xs, xe] {
                    ctx.fill(
                        Path(CGRect(x: x - 1.5, y: 0, width: 3, height: size.height)),
                        with: .color(Theme.text)
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - 11, y: size.height / 2 - 11, width: 22, height: 22)),
                        with: .color(Theme.text)
                    )
                    ctx.fill(
                        Path(CGRect(x: x - 3, y: size.height / 2 - 5, width: 1.6, height: 10)),
                        with: .color(Theme.bg)
                    )
                    ctx.fill(
                        Path(CGRect(x: x + 1.4, y: size.height / 2 - 5, width: 1.6, height: 10)),
                        with: .color(Theme.bg)
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        if active == nil {
                            let xs = CGFloat(start / duration) * width
                            let xe = CGFloat(end / duration) * width
                            active = abs(value.startLocation.x - xs) <= abs(value.startLocation.x - xe) ? 0 : 1
                        }
                        let fraction = min(max(value.location.x / width, 0), 1)
                        let time = Double(fraction) * duration
                        if active == 0 {
                            start = min(max(time, 0), end - minLength)
                        } else {
                            end = max(min(time, duration), start + minLength)
                        }
                    }
                    .onEnded { _ in active = nil }
            )
        }
        .frame(height: 124)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.bg)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 구간 자르기 화면
@MainActor
struct TrimView: View {
    let track: Track

    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = PreviewPlayer()

    @State private var peaks: [Float] = []
    @State private var loadingWave = true
    @State private var start: Double = 0
    @State private var end: Double
    @State private var replaceOriginal = false
    @State private var working = false
    @State private var saved = false
    @State private var errorText: String?

    init(track: Track) {
        self.track = track
        _end = State(initialValue: track.duration)
    }

    private var keptLength: Double { max(0, end - start) }
    private var changed: Bool { start > 0.05 || end < track.duration - 0.05 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("구간 자르기")
                        .font(Theme.heading(22))
                    Text(track.title)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                }
                .padding(.top, 24)

                ZStack {
                    WaveformSelector(
                        peaks: peaks,
                        duration: track.duration,
                        start: $start,
                        end: $end,
                        playhead: preview.isPlaying ? preview.position : nil
                    )
                    if loadingWave {
                        Text("파형을 불러오는 중…")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.muted)
                            .padding(8)
                            .background(Capsule().fill(Theme.bg.opacity(0.8)))
                    }
                }
                Text("손잡이를 끌어서 남길 구간을 정하세요.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.dim)

                HStack {
                    stepper(label: "시작", value: start) { delta in
                        start = min(max(0, start + delta), end - 0.5)
                    }
                    Spacer()
                    stepper(label: "끝", value: end) { delta in
                        end = max(min(track.duration, end + delta), start + 0.5)
                    }
                }

                Button {
                    togglePreview()
                } label: {
                    Label(preview.isPlaying ? "멈춤" : "선택한 구간 듣기", systemImage: preview.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(GhostButtonStyle())

                Text("남는 길이 \(formatPrecise(keptLength))")
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity)

                Picker("저장 방식", selection: $replaceOriginal) {
                    Text("새 곡으로 저장").tag(false)
                    Text("원본에 덮어쓰기").tag(true)
                }
                .pickerStyle(.segmented)

                if let errorText = errorText {
                    Text(errorText)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.danger)
                }

                Button {
                    save()
                } label: {
                    if working {
                        ProgressView().tint(Theme.amberInk)
                    } else if saved {
                        Label("저장했어요", systemImage: "checkmark")
                    } else {
                        Text("적용하기")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!changed || working || saved)
                .opacity(!changed || working || saved ? 0.55 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .appScreen()
        .presentationDragIndicator(.visible)
        .task {
            peaks = await AudioTools.waveform(url: Paths.audioURL(track))
            loadingWave = false
        }
        .onDisappear { preview.stop() }
    }

    private func stepper(label: String, value: Double, onChange: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 4) {
            Button { onChange(-0.1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.s2))
            }
            VStack(spacing: 0) {
                Text(formatPrecise(value))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            }
            .frame(minWidth: 62)
            Button { onChange(0.1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.s2))
            }
        }
        .buttonStyle(.plain)
    }

    private func togglePreview() {
        if !preview.isPlaying {
            player.pause()
        }
        preview.toggle(url: Paths.audioURL(track), start: start, end: end)
    }

    private func save() {
        preview.stop()
        working = true
        errorText = nil
        let from = start
        let to = end
        let replace = replaceOriginal
        let source = track

        Task { @MainActor in
            let tmp = Paths.tempURL(ext: "m4a")
            defer { try? FileManager.default.removeItem(at: tmp) }
            do {
                try await AudioTools.trim(src: Paths.audioURL(source), start: from, end: to, to: tmp)
                let newDuration = await AudioTools.duration(of: tmp)
                guard newDuration > 0 else { throw ImportError.unplayable }

                let newID = Track.newID()
                let newFile = newID + ".m4a"
                let newURL = Paths.audio.appendingPathComponent(newFile)
                try FileManager.default.moveItem(at: tmp, to: newURL)

                if replace {
                    var updated = source
                    updated.fileName = newFile
                    updated.duration = newDuration
                    try? FileManager.default.removeItem(at: Paths.audioURL(source))
                    library.update(updated)
                    player.trackFileChanged(updated)
                } else {
                    var coverName: String? = nil
                    if let oldCover = Paths.coverURL(source) {
                        let name = newID + ".jpg"
                        let destCover = Paths.covers.appendingPathComponent(name)
                        if (try? FileManager.default.copyItem(at: oldCover, to: destCover)) != nil {
                            coverName = name
                        }
                    }
                    let copy = Track(
                        id: newID,
                        title: source.title + " (편집)",
                        artist: source.artist,
                        duration: newDuration,
                        fileName: newFile,
                        coverFileName: coverName,
                        sourceURL: nil
                    )
                    library.add(copy)
                }
                working = false
                saved = true
                try? await Task.sleep(nanoseconds: 700_000_000)
                dismiss()
            } catch {
                working = false
                errorText = error.localizedDescription
            }
        }
    }
}
