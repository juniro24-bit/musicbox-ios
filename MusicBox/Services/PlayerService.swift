import AVFoundation
import Foundation
import MediaPlayer
import UIKit

/// 재생 엔진: 대기열, 셔플/반복, 백그라운드 재생, 잠금화면 컨트롤
@MainActor
final class PlayerService: ObservableObject {
    enum RepeatMode: String {
        case off, all, one
    }

    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var errorText: String?

    @Published var shuffle: Bool {
        didSet {
            UserDefaults.standard.set(shuffle, forKey: "shuffle")
            if let id = current?.id { rebuildQueue(startID: id) }
        }
    }
    @Published var repeatMode: RepeatMode {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeat") }
    }
    @Published var speed: Double {
        didSet {
            UserDefaults.standard.set(speed, forKey: "speed")
            applySpeed()
        }
    }

    /// 10초 이상 들으면 한 번 불려요 (재생 횟수 집계용)
    var onPlayed: ((String) -> Void)?

    private let player = AVPlayer()
    private var baseList: [Track] = []
    private var queue: [Track] = []
    private var index = 0
    private var counted = false
    private var timeToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        shuffle = defaults.bool(forKey: "shuffle")
        repeatMode = RepeatMode(rawValue: defaults.string(forKey: "repeat") ?? "") ?? .off
        let savedSpeed = defaults.double(forKey: "speed")
        speed = savedSpeed > 0 ? savedSpeed : 1.0

        player.automaticallyWaitsToMinimizeStalling = false
        configureSession()
        setupObservers()
        setupRemoteCommands()
    }

    // MARK: 오디오 세션

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupObservers() {
        timeToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.tick(seconds) }
        }

        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observed, _ in
            let playing = observed.timeControlStatus != .paused
            Task { @MainActor in self?.setPlaying(playing) }
        }

        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in self?.handleInterruption(typeValue: typeValue, optionValue: optionValue) }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in self?.handleRouteChange(reasonValue: reasonValue) }
        }
    }

    private func handleInterruption(typeValue: UInt?, optionValue: UInt?) {
        guard let typeValue = typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .ended, let optionValue = optionValue {
            let options = AVAudioSession.InterruptionOptions(rawValue: optionValue)
            if options.contains(.shouldResume) {
                activateSession()
                player.play()
            }
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue = reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        // 이어폰을 뽑으면 멈춰요
        if reason == .oldDeviceUnavailable {
            player.pause()
        }
    }

    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                let target = event.positionTime
                Task { @MainActor in self?.seek(to: target) }
            }
            return .success
        }
    }

    // MARK: 재생 제어

    func play(_ list: [Track], startAt track: Track) {
        baseList = list
        rebuildQueue(startID: track.id)
        load(index: index, autoplay: true, startAt: 0)
    }

    private func rebuildQueue(startID: String) {
        if shuffle {
            var rest = baseList.filter { $0.id != startID }.shuffled()
            if let first = baseList.first(where: { $0.id == startID }) {
                rest.insert(first, at: 0)
            }
            queue = rest
            index = 0
        } else {
            queue = baseList
            index = baseList.firstIndex(where: { $0.id == startID }) ?? 0
        }
    }

    private func load(index newIndex: Int, autoplay: Bool, startAt: Double) {
        guard queue.indices.contains(newIndex) else { return }
        index = newIndex
        let track = queue[newIndex]
        let url = Paths.audioURL(track)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorText = "\"\(track.title)\" 파일을 찾을 수 없어요."
            return
        }
        errorText = nil

        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        if let old = endObserver {
            NotificationCenter.default.removeObserver(old)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.itemEnded() }
        }

        player.replaceCurrentItem(with: item)
        player.defaultRate = Float(speed)
        current = track
        duration = track.duration
        position = startAt
        counted = false

        if startAt > 0 {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
        }
        if autoplay {
            activateSession()
            player.play()
        }
        updateNowPlaying()
    }

    func togglePlay() {
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard current != nil else { return }
        activateSession()
        player.play()
    }

    func pause() {
        player.pause()
    }

    func next(auto: Bool = false) {
        guard !queue.isEmpty else { return }
        var target = index + 1
        if target >= queue.count {
            if repeatMode == .all || !auto {
                target = 0
            } else {
                // 끝까지 다 들었으면 처음 위치에서 멈춰요
                player.pause()
                seek(to: 0)
                return
            }
        }
        load(index: target, autoplay: true, startAt: 0)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if position > 3 || index == 0 {
            seek(to: 0)
            return
        }
        load(index: index - 1, autoplay: true, startAt: 0)
    }

    func seek(to seconds: Double) {
        let target = max(0, seconds)
        position = target
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        updateNowPlaying()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        queue = []
        baseList = []
        index = 0
        position = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func itemEnded() {
        if repeatMode == .one {
            seek(to: 0)
            activateSession()
            player.play()
        } else {
            next(auto: true)
        }
    }

    private func applySpeed() {
        player.defaultRate = Float(speed)
        if isPlaying {
            player.rate = Float(speed)
        }
        updateNowPlaying()
    }

    // MARK: 라이브러리 변경 반영

    func trackDeleted(id: String) {
        if current?.id == id {
            stop()
            return
        }
        baseList.removeAll { $0.id == id }
        if let removedIndex = queue.firstIndex(where: { $0.id == id }) {
            queue.remove(at: removedIndex)
            if removedIndex < index { index -= 1 }
        }
    }

    func trackUpdated(_ track: Track) {
        replaceInLists(track)
        if current?.id == track.id {
            current = track
            updateNowPlaying()
        }
    }

    /// 오디오 파일 자체가 바뀐 경우(원본 덮어쓰기): 같은 위치에서 다시 불러와요
    func trackFileChanged(_ track: Track) {
        replaceInLists(track)
        guard current?.id == track.id,
              let i = queue.firstIndex(where: { $0.id == track.id }) else { return }
        let wasPlaying = isPlaying
        let resumeAt = min(position, max(0, track.duration - 0.5))
        load(index: i, autoplay: wasPlaying, startAt: resumeAt)
    }

    private func replaceInLists(_ track: Track) {
        if let i = baseList.firstIndex(where: { $0.id == track.id }) { baseList[i] = track }
        if let i = queue.firstIndex(where: { $0.id == track.id }) { queue[i] = track }
    }

    // MARK: 상태 갱신

    private func setPlaying(_ playing: Bool) {
        isPlaying = playing
        updateNowPlaying()
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = seconds
        if let item = player.currentItem {
            let d = item.duration.seconds
            if d.isFinite && d > 0 { duration = d }
        }
        if !counted && seconds > 10, let id = current?.id {
            counted = true
            onPlayed?(id)
        }
    }

    private func updateNowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0.0
        ]
        if let image = CoverCache.image(for: track) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
