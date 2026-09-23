import Foundation

// Drives the real AppStore — the same state machine the SwiftUI views bind to —
// through a full session against a live Wordflow server. Xcode is not installed
// on this machine, so this is how the gameplay flow is actually executed rather
// than only read.

enum Report {
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var failures = 0
}

func check(_ condition: Bool, _ label: String) {
    Report.checks += 1
    print(condition ? "  ok   \(label)" : "  FAIL \(label)")
    if !condition { Report.failures += 1 }
}

func section(_ title: String) { print("\n\(title)") }

/// Every ordering of every subset of at least three letters.
func candidateWords(_ letters: [Character]) -> [String] {
    var results: [String] = []
    var seen = Set<String>()
    func permute(_ prefix: [Character], _ remaining: [Character]) {
        if prefix.count >= 3, seen.insert(String(prefix)).inserted { results.append(String(prefix)) }
        guard prefix.count < letters.count else { return }
        for index in remaining.indices {
            var next = remaining
            let character = next.remove(at: index)
            permute(prefix + [character], next)
        }
    }
    permute([], letters)
    return results.sorted { $0.count > $1.count }
}

let base = ProcessInfo.processInfo.environment["WORDFLOW_BASE_URL"] ?? "http://localhost:8099"
guard let baseURL = ServerSettings.normalize(base) else {
    print("Invalid WORDFLOW_BASE_URL \(base)")
    exit(2)
}

@MainActor
func drive() async {
    let client = APIClient(baseURL: baseURL)
    await client.clearCookies()
    let store = AppStore(api: client)
    let username = "state\(String(UUID().uuidString.prefix(8)).lowercased())"

    section("Launch")
    check(store.phase == .launching, "the app starts in the launching phase")
    await store.launch()
    check(store.phase == .authentication, "no session lands on the sign-in screen")
    check(store.player == nil, "no player is loaded while signed out")

    section("Sign up")
    await store.signUp(username: username, displayName: "State Test",
                       password: "supersecret123", passwordConfirmation: "supersecret123")
    check(store.phase == .catalog, "signing up lands on the catalog")
    check(store.player?.displayName.hasPrefix("State Test#") == true, "the tagged display name is stored")
    check(store.hasCatalog, "the catalog arrives with the session response")
    check(!store.campaigns.isEmpty, "campaigns are loaded")
    check(store.standardCampaigns.count == store.campaigns.filter { !$0.isDaily }.count, "daily and standard split")

    guard let campaign = store.standardCampaigns.first else {
        check(false, "a standard campaign exists"); return
    }
    check(campaign.availableLevel?.level == 1, "level 1 is the available level")
    check(campaign.displayStatus(for: campaign.levels[0]) == .available, "display status passes through for non-locked levels")
    if let locked = campaign.levels.first(where: { $0.status == .locked && ($0.unlockedAt ?? .distantPast) > Date() }) {
        check(campaign.displayStatus(for: locked) == .locked, "a future unlock still reads as locked")
    }

    section("Start a level")
    await store.startLevel(campaignID: campaign.campaignId, level: 1)
    check(store.phase == .game, "starting a level enters the game phase")
    guard let game = store.currentGame else { check(false, "a game is loaded"); return }
    check(store.player?.activeGame?.level == 1, "the active game is recorded on the player")
    check(String(store.letterOrder).sorted() == game.letters.sorted(), "the wheel holds exactly the queue letters")
    check(store.selectedIndexes.isEmpty, "no letters start selected")
    check(store.guess.isEmpty, "the guess starts empty")
    check(store.activeCampaign?.campaignId == campaign.campaignId, "the active campaign resolves")
    check(!store.isDailyGame, "the foundations campaign is not a daily challenge")

    section("Letter wheel")
    store.select(index: 0)
    store.select(index: 1)
    check(store.guess.count == 2, "selecting two letters builds a two-letter guess")
    store.select(index: 1)
    check(store.guess.count == 2, "re-selecting a letter is ignored")
    store.trace(index: 0, allowBacktrack: false)
    check(store.guess.count == 2, "a touch-down on the previous letter is inert")
    store.trace(index: 0, allowBacktrack: true)
    check(store.guess.count == 1, "tracing back to the previous letter pops the last")
    store.trace(index: 0, allowBacktrack: true)
    check(store.guess.count == 1, "tracing back past the start is ignored")
    store.trace(index: 1, allowBacktrack: true)
    check(store.guess.count == 2, "tracing forward onto a fresh letter extends the word")
    store.trace(index: 99, allowBacktrack: true)
    check(store.guess.count == 2, "an out-of-range token is ignored")
    let beforeShuffle = store.letterOrder
    store.shuffleLetters()
    check(store.selectedIndexes.isEmpty, "shuffling clears the selection")
    check(store.letterOrder.sorted() == beforeShuffle.sorted(), "shuffling preserves the letters")
    store.select(index: 0)
    store.clearGuess()
    check(store.guess.isEmpty, "clear empties the guess")

    section("Guessing")
    // Pick three wheel positions that spell something the puzzle will reject.
    for index in 0..<min(3, store.letterOrder.count) { store.select(index: index) }
    let attempted = store.guess
    await store.submitGuess()
    check(store.selectedIndexes.isEmpty, "submitting clears the selection")
    check(store.notice != nil, "submitting raises a notice")
    check(store.currentGame?.attempts ?? 0 >= 1, "the attempt is recorded in durable state")
    print("       guessed \(attempted) -> \(store.notice?.message ?? "-")")

    section("Hints")
    let hintsBefore = store.currentGame?.hints.letters ?? 0
    await store.useHint(.letter)
    check(store.currentGame?.hints.letters == hintsBefore - 1, "a free letter hint is consumed")
    check(store.currentGame?.cells.contains { $0.hinted } == true, "the hinted cell comes back marked")
    check((store.currentGame?.hintBonus ?? 10) < 10, "the hint bonus drops")

    section("Solving")
    if let letters = store.currentGame.map({ Array($0.letters) }), letters.count <= 4 {
        for word in candidateWords(letters) where store.currentGame?.complete == false {
            store.clearGuess()
            for character in word {
                guard let index = store.letterOrder.firstIndex(where: {
                    $0 == character && !store.selectedIndexes.contains(store.letterOrder.firstIndex(of: $0) ?? -1)
                }) else { continue }
                store.select(index: index)
            }
            // Selecting by character can collide on repeated letters; fall back to
            // the ordered indices for the exact word.
            if store.guess != word {
                store.clearGuess()
                var used = Set<Int>()
                for character in word {
                    if let index = store.letterOrder.indices.first(where: {
                        store.letterOrder[$0] == character && !used.contains($0)
                    }) {
                        used.insert(index)
                        store.select(index: index)
                    }
                }
            }
            guard store.guess == word else { continue }
            await store.submitGuess()
        }
        check(store.currentGame?.complete == true, "the level completes")
        check(store.phase == .complete, "a complete game moves to the completion phase")

        // beginCompletionRefresh runs in the background; give it a moment.
        for _ in 0..<80 where !store.completionReady {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        check(store.completionReady, "the completion action resolves")
        check(store.continueTitle == "Play level 2", "the continue button offers level 2 (got \(store.continueTitle))")
        check(store.player?.activeGame == nil, "the active game is cleared")
        check(store.player?.completedLevelCount == 1, "the completed level count advances")
        check((store.player?.lifetimePointsEarned ?? 0) > 0, "lifetime points are awarded")
        check(store.campaigns.first { $0.campaignId == campaign.campaignId }?.completedLevels == 1,
              "the cached campaign card is refreshed in place")

        section("Continue")
        await store.continueFromCompletion()
        check(store.phase == .game, "continuing starts the next level")
        check(store.currentGame?.level == 2, "the next level is level 2")
        check(String(store.letterOrder).sorted() == (store.currentGame?.letters ?? "").sorted(),
              "the wheel reloads for the new level")
    }

    section("Leaving and resuming")
    await store.exitGame()
    check(store.phase == .catalog, "leaving a level returns to the catalog")
    check(store.currentGame == nil, "the game view is released")
    check(store.player?.activeGame != nil, "the level Workflow stays open")
    check(store.campaigns.first { $0.campaignId == campaign.campaignId }?.activeLevel?.level == 2,
          "the campaign card shows the active level")
    await store.resumeActiveGame()
    check(store.phase == .game, "resuming reopens the level")
    check(store.currentGame?.level == 2, "the same level resumes")

    section("Streak freeze")
    let pointsBefore = store.player?.points ?? 0
    await store.buyStreakFreeze()
    if pointsBefore >= (store.player?.streakFreezeCost ?? 50) {
        check(store.player?.streakFreeze == true, "the streak freeze is purchased")
    } else {
        check(store.player?.streakFreeze == false, "an unaffordable streak freeze is refused")
        check(store.notice?.isError == true, "the refusal is surfaced as an error notice")
    }

    section("Session lifecycle")
    await store.logOut()
    check(store.phase == .authentication, "logging out returns to the sign-in screen")
    check(store.player == nil, "the player is cleared")
    check(store.campaigns.isEmpty, "the catalog is cleared")
    check(!(await client.hasStoredSession()), "the session cookie is gone")

    await store.logIn(username: username, password: "supersecret123")
    check(store.player != nil, "logging back in restores the player")
    check(store.phase == .game, "an open level is resumed straight into the game")
    check(store.currentGame?.level == 2, "the resumed level is the one left open")

    await store.logIn(username: username, password: "not-the-password")
    check(store.notice?.isError == true, "a bad password raises an error notice")
}

await drive()
print("\n\(Report.checks - Report.failures)/\(Report.checks) checks passed")
exit(Report.failures == 0 ? 0 : 1)
