// Ports the #complete section of web/index.html, including the timed-out
// puzzle solution and its answer pills.
import SwiftUI

struct CompleteView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let game = store.currentGame {
            content(for: game)
        }
    }

    private func content(for game: Game) -> some View {
        PageScroll {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Eyebrow(text: eyebrow(for: game))
                    DisplayTitle(text: game.didTimeOut ? "Time expired." : "Execution succeeded.", size: 24)
                        .multilineTextAlignment(.center)
                    Text(summary(for: game))
                        .font(Typography.sans(15))
                        .foregroundStyle(Palette.space)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                if game.didTimeOut {
                    solution(for: game)
                }

                PendingButton(
                    title: store.continueTitle,
                    busyTitle: "Loading…",
                    style: PrimaryButtonStyle(),
                    isBusy: store.isBusy(.continueLevel),
                    isEnabled: store.completionReady
                ) {
                    Task { await store.continueFromCompletion() }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: game.didTimeOut
                        ? [Palette.dailyCream, Palette.dailyAmber]
                        : [Palette.paper, Palette.lavender],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
            .inkBorder(Metrics.cardRadius)
            .hardShadow()
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
    }

    /// `renderComplete` / `renderTimedOut`.
    private func eyebrow(for game: Game) -> String {
        guard game.didTimeOut else { return "Workflow completed" }
        return store.isDailyGame ? "Daily challenge ended" : "Level attempt ended"
    }

    private func summary(for game: Game) -> String {
        if game.didTimeOut {
            return store.isDailyGame
                ? "The hard time limit expired on level \(game.level). Today's attempt is now complete."
                : "The hard time limit expired on level \(game.level)."
        }
        guard let score = game.score else {
            return "Level \(game.level) completed after \(game.attempts) word attempt(s)."
        }
        return "Level \(game.level) completed in \(Countdown.duration(seconds: score.durationSeconds)). "
            + "Earned \(score.points) points: \(score.basePoints) win + \(score.speedBonus) speed + "
            + "\(score.accuracyBonus) accuracy + \(score.hintBonus) hint bonus."
    }

    /// `.timeout-solution` — the finished board plus every answer, marked found
    /// or missed.
    private func solution(for game: Game) -> some View {
        VStack(spacing: 14) {
            Divider().overlay(Palette.space.opacity(0.22))
            VStack(spacing: 4) {
                Text("Puzzle solution")
                    .font(Typography.display(19))
                    .foregroundStyle(Palette.space)
            }
            CrosswordGrid(cells: game.cells, rows: game.rows, columns: game.columns,
                          label: "Completed puzzle solution")
            CellLegend(includeMissed: true)
            FlowLayout(spacing: 7, alignment: .center) {
                ForEach(game.solutionWords ?? []) { word in
                    Text(word.answer.uppercased())
                        .font(Typography.sans(12, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(word.found ? Palette.uv : Palette.coral))
                        .overlay(Capsule().strokeBorder(Palette.space, lineWidth: Metrics.border))
                        .accessibilityLabel("\(word.answer). \(word.found ? "Found before time expired" : "Missed before time expired")")
                }
            }
        }
        .padding(.top, 6)
    }
}
