// Ports the .bonus-panel aside from web/index.html.
import SwiftUI

struct BonusPanel: View {
    var game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Bonus points", color: Palette.space)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .top, spacing: 8) {
                    BonusTile(
                        title: "Speed bonus",
                        value: speedValue(at: context.date),
                        detail: speedDetail(at: context.date))
                    BonusTile(
                        title: "Hint bonus",
                        value: "+\(game.hintBonus) points",
                        detail: "Hints reduce this bonus")
                    BonusTile(
                        title: "Accuracy bonus",
                        value: "+\(game.accuracyBonus) points",
                        detail: "−2 per incorrect guess")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
            .fill(LinearGradient(colors: [Palette.lime, Palette.cyan],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .inkBorder(Metrics.panelRadius)
        .hardShadow(offset: CGSize(width: 5, height: 6), color: Palette.space.opacity(0.14),
                    radius: Metrics.panelRadius)
    }

    private func speedValue(at now: Date) -> String {
        guard let bonus = game.speedBonus(at: now) else { return "0 points" }
        return "+\(bonus.points) points"
    }

    /// `renderSpeedBonus`: "1:24 until +7", or the closing message once the last
    /// tier expires.
    private func speedDetail(at now: Date) -> String {
        guard let bonus = game.speedBonus(at: now) else { return "Speed bonus window ended" }
        let remaining = Countdown.short(bonus.endsAt.timeIntervalSince(now))
        return "\(remaining) until \(bonus.next > 0 ? "+\(bonus.next)" : "0")"
    }
}

private struct BonusTile: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.sans(11, weight: .heavy))
                .foregroundStyle(Palette.space)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(Typography.display(18))
                .foregroundStyle(Palette.space)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(Typography.mono(10, weight: .regular))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Palette.space.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
