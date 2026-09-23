// Ports web/leaderboard.html + leaderboard.js — the standalone leaderboard page.

import SwiftUI

struct LeaderboardView: View {
    var onDismiss: () -> Void

    @Environment(AppStore.self) private var store
    @State private var entries: [LeaderboardEntry] = []
    @State private var status = "Connecting to the leaderboard workflow…"
    @State private var hasLoaded = false
    @State private var isLoading = false

    /// `entries.slice(0, 15)` in leaderboard.js.
    private static let visibleLimit = 15
    private static let refreshInterval = Duration.seconds(3)

    var body: some View {
        NavigationStack {
            PageScroll(onRefresh: { await refresh() }) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    StatusRail(text: "Temporal durable state · live")
                    card
                    statusLine
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .background(WordflowBackground())
            .navigationTitle("Leaderboard")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .tint(Palette.uv)
        .task { await poll() }
    }

    // MARK: - Header lockup

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            BrandMark()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: "Live durable rankings")
                DisplayTitle(text: "Wordflow Leaderboard", size: 28, trackingEm: 0.055)
                    .padding(.top, 6)
                Text("Lifetime points earned · refreshed automatically")
                    .font(Typography.sans(15))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            headingRow
            if entries.isEmpty {
                emptyState
            } else {
                let visible = Array(entries.prefix(Self.visibleLimit).enumerated())
                ForEach(visible, id: \.element.id) { index, entry in
                    row(entry, position: index, isLast: index == visible.count - 1)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .fill(Palette.paper.opacity(0.96)))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .inkBorder(Metrics.cardRadius)
        .hardShadow(offset: CGSize(width: 7, height: 8), color: Palette.space.opacity(0.12))
    }

    private var headingRow: some View {
        HStack(spacing: 10) {
            headingLabel("Rank", width: Self.rankWidth, alignment: .leading)
            headingLabel("Player", width: nil, alignment: .leading)
            headingLabel("Levels", width: Self.levelsWidth, alignment: .trailing)
            headingLabel("Points", width: Self.pointsWidth, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Self.rowInset)
        .background(Palette.space)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func headingLabel(_ text: String, width: CGFloat?, alignment: Alignment) -> some View {
        let label = Text(text.uppercased())
            .font(Typography.sans(11, weight: .heavy))
            .tracking(0.9)
            .foregroundStyle(.white)
        if let width {
            label.frame(width: width, alignment: alignment)
        } else {
            label.frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func row(_ entry: LeaderboardEntry, position: Int, isLast: Bool) -> some View {
        HStack(spacing: 10) {
            Text("#\(entry.rank)")
                .font(Typography.sans(17, weight: .bold))
                .foregroundStyle(Palette.space)
                .frame(width: Self.rankWidth, alignment: .leading)
            Text(entry.displayName)
                .font(Typography.sans(17, weight: .heavy))
                .foregroundStyle(Palette.space)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(entry.completedLevels)")
                .font(Typography.sans(17))
                .foregroundStyle(Palette.space)
                .frame(width: Self.levelsWidth, alignment: .trailing)
            Text("\(entry.lifetimePointsEarned)")
                .font(Typography.display(20))
                .foregroundStyle(Palette.uv)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.pointsWidth, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Self.rowInset)
        .frame(minHeight: 58)
        .background(alignment: .leading) { Self.wash(for: position) }
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Palette.line).frame(height: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Rank \(entry.rank), \(entry.displayName), "
            + "\(entry.completedLevels) levels, \(entry.lifetimePointsEarned) points")
    }

    /// `.leaderboard-row:nth-child(1…3)` — a podium wash that fades out to the right.
    @ViewBuilder
    private static func wash(for position: Int) -> some View {
        let tint: Color? = switch position {
        case 0: Palette.lime.opacity(0.55)
        case 1: Palette.cyan.opacity(0.4)
        case 2: Palette.pink.opacity(0.3)
        default: nil
        }
        if let tint {
            LinearGradient(colors: [tint, .clear], startPoint: .leading, endPoint: .trailing)
        }
    }

    private var emptyState: some View {
        Group {
            if hasLoaded {
                Text("Complete a wordflow to record the first score.")
                    .font(Typography.sans(15))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            } else {
                LoadingMark()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .padding(.horizontal, 24)
    }

    private var statusLine: some View {
        Text(status)
            .font(Typography.mono(11, weight: .regular))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityLabel("Leaderboard status: \(status)")
    }

    // MARK: - Polling

    private static let rankWidth: CGFloat = 52
    private static let levelsWidth: CGFloat = 54
    private static let pointsWidth: CGFloat = 78
    private static let rowInset: CGFloat = 14

    /// `setInterval(refreshLeaderboard, 3000)`. The `.task` this runs in is torn
    /// down with the sheet, so polling stops the moment the view goes away.
    @MainActor
    private func poll() async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: Self.refreshInterval)
            } catch {
                return
            }
        }
    }

    @MainActor
    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await store.leaderboard()
            hasLoaded = true
            status = "Live · updated \(Date.now.formatted(date: .omitted, time: .standard))"
        } catch {
            status = error.localizedDescription
        }
    }
}
