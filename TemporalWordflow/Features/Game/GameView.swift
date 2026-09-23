// Ports the #game section of web/index.html: heading, special event, bonus
// panel, crossword, letter queue, actions, hints and the rejected-word history.
import SwiftUI

struct GameView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let game = store.currentGame {
            content(for: game)
        }
    }

    @ViewBuilder
    private func content(for game: Game) -> some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 18) {
                heading(for: game)

                if let event = game.specialEvent {
                    eventBanner(event)
                }

                BonusPanel(game: game)

                VStack(spacing: 14) {
                    CrosswordGrid(cells: game.cells, rows: game.rows, columns: game.columns)
                    CellLegend()
                }

                VStack(spacing: 10) {
                    GuessDisplay(guess: store.guess)
                    wheel
                    actions
                    hints(for: game)
                }
                .frame(maxWidth: .infinity)

                RejectedPanel(words: game.rejected)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.paper.opacity(0.94)))
            .inkBorder(Metrics.cardRadius)
            .hardShadow()
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .task(id: game.expiresAt) { await watchDeadline(game.expiresAt) }
    }

    // MARK: - Heading

    private func heading(for game: Game) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: store.isDailyGame ? "Daily Challenge · Level \(game.level)" : "Level \(game.level)")
            DisplayTitle(text: game.title, size: 24)

            FlowLayout(spacing: 8) {
                if game.expiresAt != nil {
                    DeadlinePill(expiresAt: game.expiresAt)
                }
                metaPill("\(game.foundWords) / \(game.totalWords) words resolved")
                WorkflowLinkButton(title: "Game Workflow") {
                    Task { await store.openLevelWorkflow() }
                }
                PendingButton(
                    title: "Campaigns",
                    busyTitle: "Loading…",
                    style: QuietButtonStyle(compact: true),
                    isBusy: store.isBusy(.exitGame)
                ) {
                    Task { await store.exitGame() }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `.game-meta p` — a hairline pill around a small statistic.
    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(Typography.sans(12, weight: .semibold))
            .foregroundStyle(Palette.space)
            .padding(.vertical, 7)
            .padding(.horizontal, 11)
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
    }

    /// `.event` — the pink special-event banner.
    private func eventBanner(_ event: SpecialEvent) -> some View {
        Text("\(event.name) · +\(event.bonusPoints) points")
            .font(Typography.sans(15, weight: .semibold))
            .foregroundStyle(Palette.space)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 13)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Palette.pink, Palette.lavender],
                                     startPoint: .leading, endPoint: .trailing)))
            .inkBorder(12)
    }

    // MARK: - Letter queue

    private var wheel: some View {
        GeometryReader { proxy in
            let diameter = min(224, max(196, proxy.size.width - 32))
            LetterWheel(
                letters: store.letterOrder,
                selected: store.selectedIndexes,
                isDisabled: store.gameMutationPending,
                onSelect: { store.select(index: $0) },
                onTrace: { store.trace(index: $0, allowBacktrack: $1) },
                onSwipeComplete: { Task { await store.submitTracedGuess() } },
                diameter: diameter)
                .frame(width: proxy.size.width, alignment: .center)
        }
        .frame(height: 250)
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private var actions: some View {
        FlowLayout(spacing: 10, alignment: .center) {
            Button("Clear") { store.clearGuess() }
                .buttonStyle(QuietButtonStyle())
                .disabled(store.gameMutationPending || store.selectedIndexes.isEmpty)
                .fixedSize()

            PendingButton(
                title: "Submit word",
                busyTitle: "Submitting…",
                style: PrimaryButtonStyle(),
                isBusy: store.isBusy(.guess),
                isEnabled: !store.guess.isEmpty && !store.gameMutationPending
            ) {
                Task { await store.submitGuess() }
            }
            .frame(minWidth: 172)
            .fixedSize()

            Button("Shuffle") { store.shuffleLetters() }
                .buttonStyle(QuietButtonStyle())
                .disabled(store.gameMutationPending)
                .fixedSize()
        }
    }

    // MARK: - Hints

    private func hints(for game: Game) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.line)
            FlowLayout(spacing: 10, alignment: .center) {
                ForEach(HintKind.allCases) { hint in
                    hintButton(hint, game: game)
                }
            }
            .padding(.top, 14)
        }
    }

    /// `renderHintButton`: free inventory first, then the level's own price.
    private func hintButton(_ hint: HintKind, game: Game) -> some View {
        let remaining = hint.remaining(in: game.hints)
        let price = hint.price(in: game.hintPrices)
        let paid = remaining == 0
        let affordable = (store.player?.points ?? 0) >= price
        return PendingButton(
            title: paid ? "\(hint.label) · \(price) points" : "\(hint.label) · \(remaining) free",
            busyTitle: "Applying…",
            style: QuietButtonStyle(fill: paid ? Palette.pink : Palette.lavender, compact: false),
            isBusy: store.isBusy(.hint(hint)),
            isEnabled: !store.gameMutationPending && (!paid || affordable)
        ) {
            Task { await store.useHint(hint) }
        }
        .fixedSize()
    }

    // MARK: - Hard time limit

    /// `startLevelDeadlineTicker` + `refreshExpiredLevel`: once the durable timer
    /// passes, the level Workflow closes itself, so ask the store to poll for the
    /// timed-out view.
    private func watchDeadline(_ expiresAt: Date?) async {
        guard let expiresAt else { return }
        let delay = expiresAt.timeIntervalSinceNow
        if delay > 0 {
            let capped = min(delay, 24 * 60 * 60)
            try? await Task.sleep(nanoseconds: UInt64(capped * 1_000_000_000))
            guard !Task.isCancelled, Date() >= expiresAt else { return }
        }
        store.levelDeadlinePassed()
    }
}

/// `.level-deadline` — "Hard limit · 1:24", turning coral at zero.
private struct DeadlinePill: View {
    var expiresAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = expiresAt.map { Countdown.secondsRemaining(until: $0, now: context.date) } ?? 0
            let expired = remaining == 0
            Text(expired ? "Time expired" : "Hard limit · \(Countdown.short(seconds: remaining))")
                .font(Typography.sans(12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(expired ? Palette.coral : Palette.deadlineText)
                .padding(.vertical, 7)
                .padding(.horizontal, 11)
                .background(Capsule().fill(expired ? Palette.deadlineExpiredFill : Palette.deadlineFill))
                .overlay(Capsule().strokeBorder(expired ? Palette.coral : Palette.deadlineBorder, lineWidth: 1))
        }
        .accessibilityLabel("Level time limit")
    }
}
