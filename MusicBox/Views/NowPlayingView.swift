import SwiftUI

/// 미니 플레이어 (탭 막대 바로 위)
@MainActor
struct MiniPlayerView: View {
    @EnvironmentObject var player: PlayerService
    var onOpen: () -> Void

    var body: some View {
        if let track = player.current {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    CoverView(track: track, size: 46, corner: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist.isEmpty ? "알 수 없는 아티스트" : track.artist)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

                Button {
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.s2)
            )
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    let fraction = player.duration > 0 ? min(1, max(0, player.position / player.duration)) : 0
                    Rectangle()
                        .fill(Theme.amber)
                        .frame(width: geo.size.width * CGFloat(fraction), height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }
}

/// 전체 화면 재생 화면
@MainActor
struct NowPlayingView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerService
    @Environment(\.dismiss) private var dismiss

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var accent: Color = Theme.amber
    @State private var trimming: Track?

    private let speeds: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            LinearGradient(
                colors: [accent.opacity(0.5), Theme.bg],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            if let track = player.current {
                content(track)
            } else {
                VStack(spacing: 16) {
                    Text("재생 중인 곡이 없어요.")
                        .foregroundColor(Theme.muted)
                    Button("닫기") { dismiss() }
                        .buttonStyle(GhostButtonStyle())
                        .frame(width: 140)
                }
            }
        }
        .foregroundColor(Theme.text)
        .presentationDragIndicator(.visible)
        .onAppear { updateAccent() }
        .onChange(of: player.current?.id) { _ in updateAccent() }
        .sheet(item: $trimming) { track in
            TrimView(track: track)
        }
    }

    @ViewBuilder
    private func content(_ track: Track) -> some View {
        let live = library.track(id: track.id) ?? track
        GeometryReader { geo in
            let coverSide = min(geo.size.width - 48, geo.size.height * 0.42)
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                CoverView(track: live, size: coverSide, corner: 22)
                    .shadow(color: accent.opacity(0.45), radius: 30, y: 16)
                    .scaleEffect(player.isPlaying ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75), value: player.isPlaying)
                Spacer(minLength: 20)

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(live.title)
                            .font(Theme.heading(24))
                            .lineLimit(2)
                        Text(live.artist.isEmpty ? "알 수 없는 아티스트" : live.artist)
                            .font(.system(size: 17))
                            .foregroundColor(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        if let updated = library.toggleFavorite(id: live.id) {
                            player.trackUpdated(updated)
                        }
                    } label: {
                        Image(systemName: live.favorite ? "heart.fill" : "heart")
                            .font(.system(size: 24))
                            .foregroundColor(live.favorite ? Theme.heart : Theme.muted)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                seekBar
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                controls
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                if let error = player.errorText {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.danger)
                        .padding(.top, 8)
                }

                extras(live)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
        }
    }

    private var seekBar: some View {
        VStack(spacing: 0) {
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : min(player.position, max(player.duration, 0.1)) },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(player.duration, 0.1),
                onEditingChanged: { editing in
                    if editing {
                        scrubValue = player.position
                        scrubbing = true
                    } else {
                        player.seek(to: scrubValue)
                        scrubbing = false
                    }
                }
            )
            .tint(Theme.text)
            HStack {
                Text(formatTime(scrubbing ? scrubValue : player.position))
                Spacer()
                Text("-" + formatTime(max(0, player.duration - (scrubbing ? scrubValue : player.position))))
            }
            .font(.system(size: 13).monospacedDigit())
            .foregroundColor(Theme.muted)
        }
    }

    private var controls: some View {
        HStack {
            Button {
                player.shuffle.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(player.shuffle ? Theme.amber : Theme.muted)
                    .frame(width: 48, height: 48)
            }
            Spacer()
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30))
                    .frame(width: 56, height: 56)
            }
            Spacer()
            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Theme.bg)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Theme.text))
            }
            Spacer()
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
                    .frame(width: 56, height: 56)
            }
            Spacer()
            Button {
                cycleRepeat()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(player.repeatMode == .off ? Theme.muted : Theme.amber)
                    .frame(width: 48, height: 48)
            }
        }
        .buttonStyle(.plain)
    }

    private func extras(_ track: Track) -> some View {
        HStack {
            Spacer()
            Menu {
                Picker("재생 속도", selection: Binding(
                    get: { player.speed },
                    set: { player.speed = $0 }
                )) {
                    ForEach(speeds, id: \.self) { value in
                        Text(value == 1.0 ? "보통 (1배)" : "\(value.formatted())배").tag(value)
                    }
                }
            } label: {
                extraLabel(
                    symbol: "speedometer",
                    title: player.speed == 1.0 ? "속도" : "\(player.speed.formatted())배",
                    highlighted: player.speed != 1.0
                )
            }
            Spacer()
            Button {
                trimming = track
            } label: {
                extraLabel(symbol: "scissors", title: "자르기", highlighted: false)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private func extraLabel(symbol: String, title: String, highlighted: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 20))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(highlighted ? Theme.amber : Theme.muted)
        .frame(minWidth: 64, minHeight: 44)
    }

    private func cycleRepeat() {
        switch player.repeatMode {
        case .off: player.repeatMode = .all
        case .all: player.repeatMode = .one
        case .one: player.repeatMode = .off
        }
    }

    private func updateAccent() {
        guard let track = player.current,
              let image = CoverCache.image(for: track),
              let color = ImageTools.averageColor(of: image) else {
            accent = Theme.amber
            return
        }
        accent = color
    }
}
