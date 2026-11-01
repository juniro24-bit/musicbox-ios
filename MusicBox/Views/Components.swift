import SwiftUI
import UIKit

/// 커버 이미지 (없으면 곡마다 다른 색의 자리표시)
struct CoverView: View {
    let track: Track?
    var size: CGFloat = 52
    var corner: CGFloat = 10

    private var hue: Double {
        guard let id = track?.id else { return 0.6 }
        var value = 7
        for scalar in id.unicodeScalars {
            value = (value * 31 + Int(scalar.value)) % 360
        }
        return Double(value) / 360
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.38, brightness: 0.46),
                    Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.42, brightness: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let image = CoverCache.image(for: track) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

enum AppTab {
    case library
    case add
}

/// 아래쪽 탭 막대
struct TabBar: View {
    @Binding var tab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            item(.library, title: "라이브러리", symbol: "music.note.list")
            item(.add, title: "가져오기", symbol: "arrow.down.circle")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Theme.bg.opacity(0.95))
    }

    private func item(_ target: AppTab, title: String, symbol: String) -> some View {
        Button {
            tab = target
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .regular))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(tab == target ? Theme.amber : Theme.muted)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 곡 목록 한 줄
struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    var onTap: () -> Void
    var onFavorite: () -> Void
    var onInfo: () -> Void
    var onTrim: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    CoverView(track: track)
                    if isCurrent {
                        Color.black.opacity(0.5)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Image(systemName: isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.amber)
                    }
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isCurrent ? Theme.amber : Theme.text)
                        .lineLimit(1)
                    Text(track.artist.isEmpty ? "알 수 없는 아티스트" : track.artist)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if track.favorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.heart)
                }
                Text(formatTime(track.duration))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundColor(Theme.dim)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            Menu {
                Button(action: onFavorite) {
                    Label(track.favorite ? "즐겨찾기 해제" : "즐겨찾기", systemImage: track.favorite ? "heart.slash" : "heart")
                }
                Button(action: onTrim) {
                    Label("구간 자르기", systemImage: "scissors")
                }
                Button(action: onInfo) {
                    Label("제목, 아티스트 수정", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("삭제", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.muted)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
        }
    }
}
