import Foundation

/// Countdown and duration strings, matching the helpers in
/// `internal/api/web/app.js` character for character.
enum Countdown {
    /// `formatUnlockCountdown` — `HH:MM:SS` for a level unlock timer.
    static func unlock(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(ceil(remaining)))
        return [total / 3600, (total % 3600) / 60, total % 60]
            .map { String(format: "%02d", $0) }
            .joined(separator: ":")
    }

    /// `formatCampaignCountdown` — `DDd HH:MM:SS` for campaign availability.
    static func campaign(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(ceil(remaining)))
        let days = total / 86_400
        let rest = [(total % 86_400) / 3600, (total % 3600) / 60, total % 60]
            .map { String(format: "%02d", $0) }
            .joined(separator: ":")
        return String(format: "%02dd %@", days, rest)
    }

    /// `formatCountdown` — `M:SS` for the speed-bonus and hard-limit timers.
    static func short(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):" + String(format: "%02d", clamped % 60)
    }

    static func short(_ remaining: TimeInterval) -> String {
        short(seconds: max(0, Int(ceil(remaining))))
    }

    /// `formatDuration` — `3m 7s`, or `7s` under a minute.
    static func duration(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        return minutes > 0 ? "\(minutes)m \(clamped % 60)s" : "\(clamped % 60)s"
    }

    /// Whole seconds remaining, rounded the way the web timers round.
    static func secondsRemaining(until date: Date, now: Date = Date()) -> Int {
        max(0, Int(ceil(date.timeIntervalSince(now))))
    }
}

extension Game {
    /// `renderSpeedBonus`: the first tier that has not expired, plus the value
    /// the bonus drops to when it does.
    func speedBonus(at now: Date = Date()) -> (points: Int, next: Int, endsAt: Date)? {
        let tiers = self.tiers
        guard let index = tiers.firstIndex(where: { now <= $0.endsAt }) else { return nil }
        let next = index + 1 < tiers.count ? tiers[index + 1].points : 0
        return (tiers[index].points, next, tiers[index].endsAt)
    }
}
