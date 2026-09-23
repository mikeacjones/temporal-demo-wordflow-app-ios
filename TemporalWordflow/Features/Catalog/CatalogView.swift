// Ports the #stats, #point-shop and #catalog sections of web/index.html, and
// renderPlayer() / renderCatalog() in web/app.js.

import SwiftUI

@MainActor
struct CatalogView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        PageScroll(onRefresh: { await store.refreshCatalogQuietly() }) {
            VStack(alignment: .leading, spacing: 0) {
                if let player = store.player {
                    stats(player)
                        .padding(.top, 18)
                    pointShop(player)
                        .padding(.top, 18)
                }
                if let daily = store.dailyChallenge {
                    DailyChallengeStrip(campaign: daily)
                        .padding(.top, 26)
                }
                DisplayTitle(text: "Campaigns", size: 24)
                    .padding(.top, 26)
                    .padding(.bottom, 14)
                campaigns
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 34)
        }
    }

    // MARK: - Stats

    /// `renderPlayer` — five `.stat` tiles; the stylesheet tints only the first three.
    private func stats(_ player: Player) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            StatTile(value: "\(player.currentStreak)", label: "current streak", fill: Palette.lavender)
            StatTile(value: "\(player.bestStreak)", label: "best streak", fill: Palette.cyan)
            StatTile(value: "\(player.points)", label: "points", fill: Palette.lime)
            StatTile(value: "\(player.lifetimePointsEarned)", label: "lifetime earned",
                     fill: Palette.paper.opacity(0.94))
            StatTile(value: "\(player.completedLevelCount)", label: "levels completed",
                     fill: Palette.paper.opacity(0.94))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player statistics")
    }

    // MARK: - Point shop

    private func pointShop(_ player: Player) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.streakFreeze ? "Streak freeze ready" : "Streak freeze")
                    .font(Typography.sans(16, weight: .bold))
                    .foregroundStyle(Palette.space)
                Text("Automatically protects one missed streak day.")
                    .font(Typography.sans(12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PendingButton(
                title: player.streakFreeze ? "Purchased" : "Buy · \(player.streakFreezeCost) points",
                busyTitle: "Buying…",
                style: QuietButtonStyle(),
                isBusy: store.isBusy(.streakFreeze),
                isEnabled: !player.streakFreeze && player.points >= player.streakFreezeCost
            ) {
                Task { await store.buyStreakFreeze() }
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
            .fill(LinearGradient(
                colors: [Palette.paper, Palette.lavender],
                startPoint: .topLeading, endPoint: .trailing)))
        .inkBorder(Metrics.panelRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Point purchases")
    }

    // MARK: - Campaigns

    @ViewBuilder
    private var campaigns: some View {
        if store.hasCatalog {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(store.standardCampaigns) { campaign in
                    CampaignCard(campaign: campaign)
                }
            }
        } else {
            LoadingPanel(title: "Loading campaigns", subtitle: "Reading durable state…")
        }
    }
}
