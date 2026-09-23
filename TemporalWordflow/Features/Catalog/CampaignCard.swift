// Ports renderCampaign() in web/app.js — one .campaign-card inside #campaigns.

import Foundation
import SwiftUI

@MainActor
struct CampaignCard: View {
    var campaign: Campaign

    @Environment(AppStore.self) private var store

    /// The unlock deadline the countdown has already crossed, so the locked
    /// button becomes playable without waiting for the next catalog read, as
    /// startCampaignTicker does. Recorded as the date rather than a flag so a
    /// refresh that moves the deadline on re-locks the button.
    @State private var elapsedUnlock: Date?

    private var unlockElapsed: Bool {
        guard let elapsedUnlock, let pending = campaign.nextLevelView?.unlockedAt else { return false }
        return elapsedUnlock == pending
    }

    private var busyKey: AppStore.Busy { .campaign(campaign.campaignId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: campaign.status.rawValue)
                .padding(.bottom, 4)
            Text(campaign.title)
                .font(Typography.display(22))
                .foregroundStyle(Palette.space)
                .fixedSize(horizontal: false, vertical: true)
            availability
            WorkflowLinkButton(title: "Campaign Workflow", action: openWorkflow)
                .padding(.top, 14)
            Text(campaign.description)
                .font(Typography.sans(16))
                .lineSpacing(4)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .padding(.bottom, 18)
            Text(progressLine)
                .font(Typography.sans(13, weight: .heavy))
                .foregroundStyle(Palette.space)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            levels
                .padding(.bottom, 18)
            action
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(LinearGradient(
                colors: [Palette.paper, Palette.lavender],
                startPoint: .topLeading, endPoint: .bottomTrailing)))
        .inkBorder(15)
    }

    // MARK: - Heading

    @ViewBuilder
    private var availability: some View {
        if let endsAt = campaign.endsAt {
            availabilityLine(endsAt: endsAt)
                .font(Typography.sans(12, weight: .heavy))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
        }
    }

    @ViewBuilder
    private func availabilityLine(endsAt: Date) -> some View {
        if campaign.status == .upcoming, let startsAt = campaign.startsAt {
            countdownLine(prefix: "Starts in ", target: startsAt)
        } else if campaign.status == .active {
            countdownLine(prefix: "Available for ", target: endsAt)
        } else {
            Text("Campaign ended")
        }
    }

    private func countdownLine(prefix: String, target: Date) -> some View {
        CountdownText(
            target: target,
            style: .campaign,
            prefix: prefix,
            digitFont: Typography.mono(12, weight: .heavy),
            digitColor: Palette.space,
            onReachedZero: { store.catalogBoundaryReached(target) })
    }

    private var progressLine: String {
        let counts = "\(campaign.completedLevels) / \(campaign.totalLevels) levels completed"
        return campaign.hasFailed ? "Attempt ended · " + counts : counts
    }

    // MARK: - Level chips

    @ViewBuilder
    private var levels: some View {
        if campaign.levels.contains(where: { $0.status == .locked && $0.unlockedAt != nil }) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                chips(now: context.date)
            }
        } else {
            chips(now: Date())
        }
    }

    private func chips(now: Date) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(campaign.levels) { level in
                LevelChip(level: level, status: chipStatus(for: level, now: now))
            }
        }
    }

    /// The ticker promotes the pending chip to `available` at the same moment it
    /// enables the start button.
    private func chipStatus(for level: LevelView, now: Date) -> LevelStatus {
        if unlockElapsed, level.level == campaign.nextLevel { return .available }
        return campaign.displayStatus(for: level, now: now)
    }

    // MARK: - Action

    @ViewBuilder
    private var action: some View {
        if let active = campaign.activeLevel {
            PendingButton(
                title: "Resume level \(active.level)",
                busyTitle: "Resuming…",
                style: PrimaryButtonStyle(),
                isBusy: store.isBusy(busyKey)
            ) {
                Task { await store.resumeActiveGame() }
            }
        } else if let available = campaign.availableLevel {
            PendingButton(
                title: campaign.completedLevels > 0 ? "Continue campaign" : "Start campaign",
                busyTitle: "Starting…",
                style: PrimaryButtonStyle(),
                isBusy: store.isBusy(busyKey)
            ) {
                Task { await store.startLevel(campaignID: campaign.campaignId, level: available.level) }
            }
        } else if campaign.isComplete {
            lockedButton("Campaign complete")
        } else if (campaign.lockedReason ?? "").isEmpty,
                  let next = campaign.nextLevelView,
                  let unlockedAt = next.unlockedAt {
            unlockButton(level: next.level, unlockedAt: unlockedAt)
        } else {
            lockedButton(campaign.lockedReason ?? "Next level locked")
        }
    }

    @ViewBuilder
    private func unlockButton(level: Int, unlockedAt: Date) -> some View {
        if unlockElapsed {
            PendingButton(
                title: "Start level \(level)",
                busyTitle: "Starting…",
                style: PrimaryButtonStyle(),
                isBusy: store.isBusy(busyKey)
            ) {
                Task { await store.startLevel(campaignID: campaign.campaignId, level: level) }
            }
        } else {
            Button {} label: {
                CountdownText(
                    target: unlockedAt,
                    style: .unlock,
                    prefix: "Level \(level) unlocks in ",
                    digitFont: Typography.mono(15, weight: .heavy),
                    onReachedZero: { elapsedUnlock = unlockedAt })
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func lockedButton(_ title: String) -> some View {
        Button(title) {}
            .buttonStyle(QuietButtonStyle())
            .disabled(true)
    }

    private func openWorkflow() {
        store.openCampaignWorkflow(campaign)
    }
}
