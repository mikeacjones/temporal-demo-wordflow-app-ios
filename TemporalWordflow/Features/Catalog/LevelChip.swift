// Ports the .campaign-level squares and the .daily-progress pips of web/styles.css.

import SwiftUI

/// `.campaign-level` — the 30px rounded square that carries a level number, or
/// a coral padlock once the level is locked behind an unlock timer.
struct LevelChip: View {
    var level: LevelView
    var status: LevelStatus

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                .fill(fill)
            RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
            if status == .locked {
                PadlockGlyph()
            } else {
                Text("\(level.level)")
                    .font(Typography.sans(12, weight: .heavy))
                    .foregroundStyle(number)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(levelAccessibilityLabel(level, status))
    }

    private var fill: Color {
        switch status {
        case .locked: Palette.paper
        case .unlocked: Palette.lavender
        case .available: Palette.uv
        case .active: Palette.pink
        case .complete: Palette.lime
        }
    }

    private var border: Color {
        switch status {
        case .locked: Palette.line
        case .unlocked: Palette.levelUnlockedBorder
        case .available, .active, .complete: Palette.space
        }
    }

    private var number: Color {
        status == .available ? .white : Palette.space
    }
}

/// `.daily-progress span` — the same states as a circular pip on the gold strip.
struct DailyLevelPip: View {
    var level: LevelView
    var status: LevelStatus

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(border, lineWidth: borderWidth)
            Text("\(level.level)")
                .font(Typography.sans(11, weight: .heavy))
                .foregroundStyle(number)
        }
        .frame(width: 26, height: 26)
        .opacity(status == .locked ? 0.42 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(levelAccessibilityLabel(level, status))
    }

    private var isNeutral: Bool {
        status == .locked || status == .unlocked
    }

    private var fill: Color {
        switch status {
        case .locked, .unlocked: Palette.paper.opacity(0.62)
        case .available: Palette.gold
        case .active: Palette.pink
        case .complete: Palette.lime
        }
    }

    private var border: Color {
        isNeutral ? Palette.space.opacity(0.3) : Palette.space
    }

    private var borderWidth: CGFloat {
        isNeutral ? 1 : Metrics.border
    }

    private var number: Color {
        isNeutral ? Palette.dailyDetail : Palette.space
    }
}

/// `title="Level 3: Durable State · available"` on both chip variants.
private func levelAccessibilityLabel(_ level: LevelView, _ status: LevelStatus) -> String {
    "Level \(level.level): \(level.title) · \(status.rawValue)"
}

/// `.campaign-level.locked::before` / `::after` — a 9×8 arc-topped shackle over
/// a 15×11 body, both coral at .68 opacity.
private struct PadlockGlyph: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            Shackle()
                .strokeBorder(Palette.coral, lineWidth: 2)
                .frame(width: 9, height: 8)
                .offset(y: 6)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Palette.coral)
                .frame(width: 15, height: 11)
                .offset(y: 13)
        }
        .opacity(0.68)
        .accessibilityHidden(true)
    }
}

private struct Shackle: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = CGRect(
            x: rect.minX + inset,
            y: rect.minY + inset,
            width: max(0, rect.width - inset * 2),
            height: max(0, rect.height - inset))
        let radius = min(box.width / 2, box.height)
        var path = Path()
        path.move(to: CGPoint(x: box.minX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + radius))
        path.addArc(
            center: CGPoint(x: box.minX + radius, y: box.minY + radius),
            radius: radius,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: box.maxX - radius, y: box.minY))
        path.addArc(
            center: CGPoint(x: box.maxX - radius, y: box.minY + radius),
            radius: radius,
            startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        return path
    }

    func inset(by amount: CGFloat) -> Shackle {
        Shackle(inset: inset + amount)
    }
}
