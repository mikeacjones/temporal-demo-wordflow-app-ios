// Ports renderDailyChallenge() in web/app.js — the .daily-strip gold banner
// that #daily-challenge-slot holds.

import Foundation
import SwiftUI

@MainActor
struct DailyChallengeStrip: View {
    var campaign: Campaign

    @Environment(AppStore.self) private var store

    private var terminal: Bool {
        campaign.hasFailed || campaign.completedLevels == campaign.totalLevels
    }

    private var busyKey: AppStore.Busy { .campaign(campaign.campaignId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                mark
                copy
            }
            progress
            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, terminal ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .inkBorder(Metrics.panelRadius, color: Palette.dailyBorder)
        .hardShadow(
            offset: terminal ? CGSize(width: 3, height: 4) : CGSize(width: 5, height: 6),
            color: Palette.dailyBorder.opacity(terminal ? 0.16 : 0.2),
            radius: Metrics.panelRadius)
    }

    // MARK: - Chrome

    private var background: some View {
        RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
            .fill(LinearGradient(
                colors: [Palette.dailyCream, campaign.hasFailed ? Palette.dailyAmberFailed : Palette.dailyAmber],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RadialGradient(
                    colors: [Palette.paper.opacity(0.8), .clear],
                    center: UnitPoint(x: 0.92, y: 0.1),
                    startRadius: 0, endRadius: 160)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)))
    }

    /// `.daily-mark` — ✦ while the challenge is live, ✓ / × once it is settled.
    private var mark: some View {
        let side: CGFloat = terminal ? 36 : 44
        let radius: CGFloat = terminal ? 11 : 13
        return Text(terminal ? (campaign.hasFailed ? "×" : "✓") : "✦")
            .font(.system(size: terminal ? 16 : 21, weight: .black))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(campaign.hasFailed ? Palette.coral : Palette.dailyMark))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.space, lineWidth: Metrics.border))
            .accessibilityHidden(true)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: eyebrow, color: Palette.dailyEyebrow)
            Text(title)
                .font(Typography.display(17))
                .foregroundStyle(Palette.space)
                .lineLimit(1)
                .truncationMode(.tail)
            detail
                .font(Typography.sans(12, weight: .bold))
                .foregroundStyle(Palette.dailyDetail)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrow: String {
        guard terminal else { return "Daily Challenge" }
        return campaign.hasFailed ? "Daily challenge ended" : "Daily challenge complete"
    }

    private var title: String {
        terminal
            ? "\(campaign.completedLevels) / \(campaign.totalLevels) levels completed"
            : campaign.title
    }

    @ViewBuilder
    private var detail: some View {
        if terminal {
            countdownLine(prefix: "Returns in ", target: campaign.endsAt)
        } else if campaign.status == .upcoming {
            countdownLine(
                prefix: "\(campaign.totalLevels) expert levels · Starts in ",
                target: campaign.startsAt)
        } else {
            countdownLine(
                prefix: "\(campaign.totalLevels) expert levels · Hard time limits · ",
                target: campaign.endsAt,
                suffix: " left")
        }
    }

    @ViewBuilder
    private func countdownLine(prefix: String, target: Date?, suffix: String = "") -> some View {
        if let target {
            CountdownText(
                target: target,
                style: .campaign,
                prefix: prefix,
                suffix: suffix,
                digitFont: Typography.mono(12, weight: .bold),
                onReachedZero: { store.catalogBoundaryReached(target) })
        } else {
            Text(prefix.trimmingCharacters(in: CharacterSet(charactersIn: " ·")))
        }
    }

    // MARK: - Level pips

    @ViewBuilder
    private var progress: some View {
        if campaign.levels.contains(where: { $0.status == .locked && $0.unlockedAt != nil }) {
            // Mirrors the [data-locks-until] pass in startCampaignTicker: a pip
            // flips to unlocked the moment its timer elapses.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                pips(now: context.date)
            }
        } else {
            pips(now: Date())
        }
    }

    private func pips(now: Date) -> some View {
        FlowLayout(spacing: 5) {
            ForEach(campaign.levels) { level in
                DailyLevelPip(level: level, status: campaign.displayStatus(for: level, now: now))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(campaign.completedLevels) of \(campaign.totalLevels) daily levels completed")
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            WorkflowLinkButton(title: "Workflow", action: openWorkflow)
            action
        }
    }

    @ViewBuilder
    private var action: some View {
        if terminal {
            PendingButton(
                title: campaign.hasFailed ? "View solution" : "View result",
                busyTitle: "Loading result…",
                style: QuietButtonStyle(),
                isBusy: store.isBusy(busyKey)
            ) {
                Task { await store.reviewOutcome(for: campaign) }
            }
        } else if let active = campaign.activeLevel {
            PendingButton(
                title: "Resume level \(active.level)",
                busyTitle: "Resuming…",
                style: dailyPrimary,
                isBusy: store.isBusy(busyKey)
            ) {
                Task { await store.resumeActiveGame() }
            }
        } else if let available = campaign.availableLevel {
            PendingButton(
                title: campaign.completedLevels > 0 ? "Continue challenge" : "Play Daily Challenge!",
                busyTitle: "Starting…",
                style: dailyPrimary,
                isBusy: store.isBusy(busyKey)
            ) {
                Task { await store.startLevel(campaignID: campaign.campaignId, level: available.level) }
            }
        } else {
            Button(campaign.lockedReason ?? "Challenge unavailable") {}
                .buttonStyle(QuietButtonStyle())
                .disabled(true)
        }
    }

    private var dailyPrimary: PrimaryButtonStyle {
        PrimaryButtonStyle(fill: Palette.dailyMark, pressedFill: Palette.dailyMarkHover)
    }

    private func openWorkflow() {
        store.openCampaignWorkflow(campaign)
    }
}
