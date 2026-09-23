import SwiftUI

// MARK: - Surfaces

/// `.stat, .card, .game { border: 2px solid var(--space); border-radius: 18px;
/// box-shadow: 6px 7px 0 rgba(20,20,20,.11) }` — a hard, blur-free offset shadow.
struct HardShadow: ViewModifier {
    var offset: CGSize = Metrics.cardShadow
    var color: Color = Palette.space.opacity(0.11)
    var radius: CGFloat = Metrics.cardRadius

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(color)
                .offset(x: offset.width, y: offset.height))
    }
}

extension View {
    func hardShadow(
        offset: CGSize = Metrics.cardShadow,
        color: Color = Palette.space.opacity(0.11),
        radius: CGFloat = Metrics.cardRadius
    ) -> some View {
        modifier(HardShadow(offset: offset, color: color, radius: radius))
    }

    func inkBorder(_ radius: CGFloat = Metrics.cardRadius, color: Color = Palette.space, width: CGFloat = Metrics.border) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: width))
    }
}

/// The recurring bordered panel: white-ish fill, ink border, hard shadow.
struct NeoPanel<Content: View>: View {
    var radius: CGFloat = Metrics.cardRadius
    var padding: CGFloat = 18
    var fill: AnyShapeStyle = AnyShapeStyle(Palette.paper.opacity(0.94))
    var border: Color = Palette.space
    var shadow: CGSize = Metrics.cardShadow
    var shadowColor: Color = Palette.space.opacity(0.11)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .inkBorder(radius, color: border)
            .hardShadow(offset: shadow, color: shadowColor, radius: radius)
    }
}

// MARK: - Type styles

/// `.eyebrow` — uppercase monospace kicker in Temporal ultraviolet.
struct Eyebrow: View {
    var text: String
    var color: Color = Palette.uv

    var body: some View {
        Text(text.uppercased())
            .font(Typography.mono(11, weight: .heavy))
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

struct DisplayTitle: View {
    var text: String
    var size: CGFloat = 34
    /// `h2 { letter-spacing: -.035em }`; pass `0.055` for an `h1` lockup.
    var trackingEm: CGFloat = 0.035

    var body: some View {
        Text(text)
            .font(Typography.display(size))
            .tracking(-size * trackingEm)
            .foregroundStyle(Palette.space)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Buttons

/// `.primary` — ultraviolet pill with a 3px ink shadow that collapses on press.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Palette.uv
    var pressedFill: Color = Palette.uvDark
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(Typography.sans(16, weight: .heavy))
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Capsule(style: .continuous).fill(pressed ? pressedFill : fill))
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.space, lineWidth: Metrics.border))
            .background(
                Capsule(style: .continuous)
                    .fill(Palette.space)
                    // `button:disabled { box-shadow: none; transform: none }`.
                    .offset(x: pressed || !isEnabled ? 0 : Metrics.buttonShadow.width,
                            y: pressed || !isEnabled ? 0 : Metrics.buttonShadow.height))
            .offset(x: pressed && isEnabled ? 2 : 0, y: pressed && isEnabled ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// `.quiet` — paper pill, lavender on press, no drop shadow.
struct QuietButtonStyle: ButtonStyle {
    var fill: Color = Palette.paper
    var foreground: Color = Palette.space
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(Typography.sans(compact ? 12 : 15, weight: .heavy))
            .foregroundStyle(foreground)
            .tint(foreground)
            .padding(.vertical, compact ? 7 : 11)
            .padding(.horizontal, compact ? 12 : 18)
            .background(Capsule(style: .continuous).fill(pressed ? Palette.lavender : fill))
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.space, lineWidth: Metrics.border))
            .offset(x: pressed ? 1 : 0, y: pressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// A button that shows a spinner and a busy label while its action runs, the
/// way `withPendingButton` does on the web.
struct PendingButton<Style: ButtonStyle>: View {
    var title: String
    var busyTitle: String
    var style: Style
    var isBusy: Bool
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(isBusy ? busyTitle : title)
                if isBusy {
                    // The button style sets `.tint`, so the spinner picks up the
                    // right colour on a paper pill as well as an ultraviolet one.
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(style)
        .disabled(isBusy || !isEnabled)
    }
}

// MARK: - Chrome

/// `.brand-mark` — the ✦ lockup tile.
struct BrandMark: View {
    var size: CGFloat = 52

    var body: some View {
        Text("✦")
            .font(.system(size: size * 0.52, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(Palette.uv))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(Palette.space, lineWidth: Metrics.border))
            .hardShadow(offset: CGSize(width: 4, height: 4), color: Palette.space, radius: size * 0.27)
    }
}

/// `.status-rail` — the black "Temporal durable state · active" strip.
struct StatusRail: View {
    var text: String = "Temporal durable state · active"
    var online = true

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(online ? Palette.lime : Palette.coral)
                .frame(width: 9, height: 9)
                // `box-shadow: 0 0 0 4px` is a ring outside the dot, not inside it.
                .background(Circle()
                    .fill((online ? Palette.lime : Palette.coral).opacity(0.16))
                    .frame(width: 17, height: 17))
            Text(text)
                .font(Typography.mono(11, weight: .medium))
                .tracking(0.3)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(Capsule(style: .continuous).fill(Palette.space))
    }
}

/// The page background: two radial washes over a 32px ultraviolet grid.
struct WordflowBackground: View {
    var body: some View {
        ZStack {
            Palette.offWhite
            GridPattern()
                .stroke(Palette.uv.opacity(0.055), lineWidth: 1)
            RadialGradient(
                colors: [Palette.uv.opacity(0.18), .clear],
                center: UnitPoint(x: 0.08, y: 0.04),
                startRadius: 0, endRadius: 400)
            RadialGradient(
                colors: [Palette.pink.opacity(0.2), .clear],
                center: UnitPoint(x: 0.9, y: 0.18),
                startRadius: 0, endRadius: 304)
        }
        .ignoresSafeArea()
    }
}

private struct GridPattern: Shape {
    var spacing: CGFloat = 32

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

/// `.notice` — the black toast pinned under the status bar.
struct NoticeBanner: View {
    var message: String

    var body: some View {
        Text(message)
            .font(Typography.sans(15, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 15)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.space))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.space, lineWidth: Metrics.border))
            .hardShadow(offset: CGSize(width: 4, height: 4), color: Palette.uv, radius: 12)
            .padding(.horizontal, Metrics.gutter)
    }
}

/// `.stat` — the pastel statistic tiles above the catalog.
struct StatTile: View {
    var value: String
    var label: String
    var fill: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Typography.display(22))
                .foregroundStyle(Palette.space)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(Typography.sans(10, weight: .heavy))
                .tracking(0.45)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(fill))
        .inkBorder(Metrics.cardRadius)
        .hardShadow()
    }
}

/// The `Workflow ↗` affordance used throughout the web UI.
struct WorkflowLinkButton: View {
    var title: String = "Workflow"
    var compact = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(title) ↗")
        }
        .buttonStyle(QuietButtonStyle(compact: compact))
    }
}

/// The three hopping squares used by `.campaign-loading-mark`. Driven off the
/// SwiftUI clock so all three stay in phase with a .14s stagger, as in the CSS.
struct LoadingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors: [Color] = [Palette.uv, Palette.cyan, Palette.lime]

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = reduceMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            HStack(spacing: 7) {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    let lift = hop(phase: phase, index: index)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color)
                        .frame(width: 11, height: 11)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Palette.space, lineWidth: Metrics.border))
                        .rotationEffect(.degrees(Double(lift) * -0.9))
                        .offset(y: lift)
                }
            }
        }
        .frame(height: 32)
        .accessibilityHidden(true)
    }

    private func hop(phase: Double, index: Int) -> CGFloat {
        var t = (phase - Double(index) * 0.14).truncatingRemainder(dividingBy: 1)
        if t < 0 { t += 1 }
        guard t < 0.6 else { return 0 }
        return -9 * sin(.pi * (t / 0.6))
    }
}

/// The "Loading campaigns / Reading durable state…" placeholder card.
struct LoadingPanel: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 7) {
            LoadingMark()
            Text(title)
                .font(Typography.sans(16, weight: .bold))
                .foregroundStyle(Palette.space)
            Text(subtitle)
                .font(Typography.mono(12, weight: .regular))
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(LinearGradient(colors: [Palette.paper, Palette.lavender],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .inkBorder(15)
    }
}
