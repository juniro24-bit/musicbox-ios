import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// 한밤의 오디오룸: 깊은 남색 바탕에 앰프 램프 같은 호박색 포인트
enum Theme {
    static let bg = Color(hex: 0x0C1120)
    static let s1 = Color(hex: 0x141A2E)
    static let s2 = Color(hex: 0x1C243F)
    static let s3 = Color(hex: 0x2A3355)
    static let text = Color(hex: 0xEEF1F8)
    static let muted = Color(hex: 0x8A93B2)
    static let dim = Color(hex: 0x3A4366)
    static let amber = Color(hex: 0xFFC857)
    static let amberInk = Color(hex: 0x231A00)
    static let danger = Color(hex: 0xFF7A85)
    static let ok = Color(hex: 0x7BE0A5)
    static let heart = Color(hex: 0xFF6B8B)

    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(Theme.amberInk)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.amber.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.s2.opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}

extension View {
    /// 모든 화면 공통: 어두운 배경과 기본 글자색
    func appScreen() -> some View {
        self
            .foregroundColor(Theme.text)
            .background(Theme.bg.ignoresSafeArea())
    }
}
