// Ports the .campaign-countdown / .campaign-unlock-countdown spans that
// campaignCountdown() creates and startCampaignTicker() drives in web/app.js.

import SwiftUI

/// A live countdown rendered inline with its surrounding copy, so
/// `"Available for 00d 04:12:07"` wraps and truncates as one sentence the way
/// the web `<p>` does.
struct CountdownText: View {
    enum Style {
        /// `formatCampaignCountdown` — `00d 04:12:07`, "now" once it elapses.
        case campaign
        /// `formatUnlockCountdown` — `04:12:07`.
        case unlock
        /// `formatCountdown` — `4:12`.
        case short
    }

    var target: Date
    var style: Style = .campaign
    var prefix: String = ""
    var suffix: String = ""
    /// The stylesheet swaps the digits to `ui-monospace` while the sentence
    /// around them keeps the sans face; `nil` leaves the inherited font alone.
    var digitFont: Font?
    /// `.campaign-countdown { color: var(--space) }` — the digits stay ink even
    /// where the line around them is muted. `nil` inherits, as the daily strip does.
    var digitColor: Color?
    var onReachedZero: (() -> Void)?

    /// The target already reported, so a boundary is announced once but a
    /// later target handed to the same view still gets its own callback.
    @State private var reportedTarget: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = target.timeIntervalSince(context.date)
            sentence(remaining: remaining)
                .tickingNumber()
                // `task(id:)` rather than `onChange(initial:)` so the flag is
                // flipped after the update instead of during it.
                .task(id: remaining <= 0) {
                    guard remaining <= 0, reportedTarget != target else { return }
                    reportedTarget = target
                    onReachedZero?()
                }
        }
    }

    private func sentence(remaining: TimeInterval) -> Text {
        var digits = Text(digits(remaining: remaining))
        if let digitFont {
            digits = digits.font(digitFont)
        }
        if let digitColor {
            digits = digits.foregroundStyle(digitColor)
        }
        return Text(prefix) + digits + Text(suffix)
    }

    private func digits(remaining: TimeInterval) -> String {
        if remaining <= 0, style == .campaign { return "now" }
        switch style {
        case .campaign: return Countdown.campaign(remaining)
        case .unlock: return Countdown.unlock(remaining)
        case .short: return Countdown.short(remaining)
        }
    }
}
