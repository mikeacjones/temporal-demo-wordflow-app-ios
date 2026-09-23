import SwiftUI

/// Colour tokens copied from `internal/api/web/styles.css` `:root`, plus the
/// literal values the stylesheet uses inline for the daily-challenge strip and
/// the level deadline pill.
enum Palette {
    static let uv = Color(hex: 0x444CE7)
    static let uvDark = Color(hex: 0x3038BD)
    static let space = Color(hex: 0x141414)
    static let offWhite = Color(hex: 0xF8FAFC)
    static let paper = Color(hex: 0xFFFFFF)
    static let muted = Color(hex: 0x626574)
    static let lavender = Color(hex: 0xE8E9FF)
    static let lime = Color(hex: 0xB7F36B)
    static let cyan = Color(hex: 0x86E8FF)
    static let pink = Color(hex: 0xFF8FC3)
    static let coral = Color(hex: 0xE85D3F)
    static let gold = Color(hex: 0xF5C451)
    static let line = Color(hex: 0xD9DCE8)

    /// `.stat span`, `.bonus-item small`
    static let ink = Color(hex: 0x41434D)

    // Daily challenge strip
    static let dailyBorder = Color(hex: 0x5C4300)
    static let dailyMark = Color(hex: 0xA56F00)
    static let dailyMarkHover = Color(hex: 0x785100)
    static let dailyEyebrow = Color(hex: 0x7A5700)
    static let dailyDetail = Color(hex: 0x665427)
    static let dailyCream = Color(hex: 0xFFFAF0)
    static let dailyAmber = Color(hex: 0xF9D979)
    static let dailyAmberFailed = Color(hex: 0xF4D9A3)

    // Level deadline pill
    static let deadlineBorder = Color(hex: 0x9A6800)
    static let deadlineText = Color(hex: 0x6F4B00)
    static let deadlineFill = Color(hex: 0xFFF0B5)
    static let deadlineExpiredFill = Color(hex: 0xFFF0EC)

    // Campaign level chip borders
    static let levelUnlockedBorder = Color(hex: 0xC7CAE5)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

/// Typography. The stylesheet asks for `Inter, ui-sans-serif, system-ui,
/// -apple-system…`; on Apple platforms that resolves to SF Pro, so the system
/// face with the stylesheet's tracking is the faithful rendering. Monospace
/// runs (`ui-monospace, SFMono-Regular`) become SF Mono.
enum Typography {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func mono(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// `h1 { letter-spacing: -.055em }` and friends, expressed in points.
    static func tightTracking(_ size: CGFloat, em: CGFloat) -> CGFloat { size * em }
}

/// Shared geometry from the stylesheet: 2px ink borders, hard (blur-free)
/// offset shadows, and generous radii.
enum Metrics {
    static let border: CGFloat = 2
    static let cardRadius: CGFloat = 18
    static let panelRadius: CGFloat = 16
    static let tileRadius: CGFloat = 7
    static let chipRadius: CGFloat = 8
    static let cardShadow = CGSize(width: 6, height: 7)
    static let buttonShadow = CGSize(width: 3, height: 3)
    static let gutter: CGFloat = 16
}
