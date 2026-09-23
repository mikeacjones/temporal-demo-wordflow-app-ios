import Foundation

// Live contract check for the Core layer.
//
// Core/ is plain Foundation, so the exact APIClient + Codable models the iOS app
// ships can be compiled for macOS and run against a real Wordflow server. This
// proves the request bodies, the response decoding, and the Go timestamp parser
// against the running API rather than against a transcription of it.

enum Report {
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var failures = 0
}

func check(_ condition: Bool, _ label: String) {
    Report.checks += 1
    if condition {
        print("  ok   \(label)")
    } else {
        Report.failures += 1
        print("  FAIL \(label)")
    }
}

func section(_ title: String) { print("\n\(title)") }

// MARK: - GoTimestamp

section("GoTimestamp")
let fixtures: [(String, Double)] = [
    ("1970-01-01T00:00:00Z", 0),
    ("2026-09-23T16:20:36Z", 1790180436),
    ("2026-09-23T16:20:36.107296Z", 1790180436.107296),
    ("2026-09-23T16:20:36.999999999Z", 1790180436.999999999),
    ("2026-09-23T11:20:36-05:00", 1790180436),
    ("2026-09-23T18:20:36+02:00", 1790180436),
    ("2024-02-29T12:00:00Z", 1709208000),
    ("2000-02-29T00:00:00Z", 951782400),
]
for (text, expected) in fixtures {
    let parsed = GoTimestamp.parse(text)
    check(parsed != nil && abs(parsed!.timeIntervalSince1970 - expected) < 0.0005,
          "\(text) -> \(parsed?.timeIntervalSince1970.description ?? "nil") (want \(expected))")
}
for bad in ["", "not-a-date", "2026-09-23", "2026-09-23T16:20:36", "2026-13-01T00:00:00Z", "2026-09-23T16:20:36.Z"] {
    check(GoTimestamp.parse(bad) == nil, "rejects \(bad.isEmpty ? "<empty>" : bad)")
}

// MARK: - Countdown formatting

section("Countdown formatting")
check(Countdown.unlock(0) == "00:00:00", "unlock at zero")
check(Countdown.unlock(59) == "00:00:59", "unlock under a minute")
check(Countdown.unlock(3661) == "01:01:01", "unlock past an hour")
check(Countdown.unlock(86_399) == "23:59:59", "unlock just under a day")
check(Countdown.unlock(-5) == "00:00:00", "unlock clamps at zero")
check(Countdown.campaign(0) == "00d 00:00:00", "campaign at zero")
check(Countdown.campaign(90_061) == "01d 01:01:01", "campaign past a day")
check(Countdown.short(seconds: 0) == "0:00", "short at zero")
check(Countdown.short(seconds: 65) == "1:05", "short past a minute")
check(Countdown.short(seconds: 600) == "10:00", "short at ten minutes")
check(Countdown.duration(seconds: 7) == "7s", "duration under a minute")
check(Countdown.duration(seconds: 187) == "3m 7s", "duration past a minute")
check(Countdown.duration(seconds: 120) == "2m 0s", "duration on the minute")

// MARK: - ServerSettings

section("ServerSettings")
check(ServerSettings.normalize("localhost:8099")?.absoluteString == "http://localhost:8099", "bare host:port gains a scheme")
check(ServerSettings.normalize("http://example.test/")?.absoluteString == "http://example.test", "trailing slash trimmed")
check(ServerSettings.normalize("https://example.test")?.absoluteString == "https://example.test", "https preserved")
check(ServerSettings.normalize("   ") == nil, "blank rejected")

// MARK: - Live API

let base = ProcessInfo.processInfo.environment["WORDFLOW_BASE_URL"] ?? "http://localhost:8099"
guard let baseURL = ServerSettings.normalize(base) else {
    print("Invalid WORDFLOW_BASE_URL \(base)")
    exit(2)
}

/// Every ordering of every subset of `letters` of at least `minimum` characters,
/// which is enough to brute-force the four-letter opening level.
func candidateWords(_ letters: String, minimum: Int = 3) -> [String] {
    let characters = Array(letters)
    var results: [String] = []
    var seen = Set<String>()

    func permute(_ prefix: [Character], _ remaining: [Character]) {
        if prefix.count >= minimum {
            let word = String(prefix)
            if seen.insert(word).inserted { results.append(word) }
        }
        guard prefix.count < characters.count else { return }
        for index in remaining.indices {
            var next = remaining
            let character = next.remove(at: index)
            permute(prefix + [character], next)
        }
    }
    permute([], characters)
    return results.sorted { $0.count > $1.count }
}

func run() async {
    section("Letter shuffle")
    let order = await AppStore.shuffled("FLOWERS")
    check(order.count == 7 && String(order).sorted() == "FLOWERS".sorted(), "shuffle preserves the multiset")
    var moved = false
    for _ in 0..<20 where await AppStore.shuffled("FLOWERS", previous: order) != order { moved = true; break }
    check(moved, "shuffle can produce a different order")

    section("Live API at \(baseURL.absoluteString)")
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let username = "smoke\(suffix)"
    let client = APIClient(baseURL: baseURL)

    do {
        let signUp = try await client.signUp(username: username, displayName: "Smoke Test",
                                            password: "supersecret123",
                                            passwordConfirmation: "supersecret123")
        check(signUp.player.displayName.hasPrefix("Smoke Test#"), "signup tags the display name (\(signUp.player.displayName))")
        check(signUp.player.streakFreezeCost == 50, "streak freeze costs 50")
        check(signUp.player.activeGame == nil, "a new player has no active game")
        check(signUp.catalog != nil, "signup returns the catalog when no level is active")

        let catalog = try await client.catalog()
        check(!catalog.campaigns.isEmpty, "catalog has campaigns")
        guard let campaign = catalog.campaigns.first(where: { !$0.isDaily }) else {
            check(false, "a non-daily campaign exists"); return
        }
        check(campaign.levels.count == campaign.totalLevels, "levels array matches totalLevels")
        check(campaign.levels.first?.status == .available, "level 1 is available")
        check(campaign.levels.contains { $0.unlockedAt != nil }, "unlock timestamps decode")
        check(URL(string: campaign.workflowUrl) != nil, "campaign workflow URL parses")

        let started = try await client.startLevel(campaignID: campaign.campaignId, level: 1)
        check(started.player.activeGame?.level == 1, "starting a level records the active game")
        var game = started.game
        check(!game.letters.isEmpty, "the level has a letter queue")
        check(game.letters.count <= 8, "letter queues stay within MaxWordflowLetters")
        check(!game.cells.isEmpty, "the level has crossword cells")
        check(game.tiers.count == 3, "three speed bonus tiers decode")
        check(game.tiers[0].points == 10 && game.tiers[1].points == 7 && game.tiers[2].points == 4,
              "speed tiers are 10/7/4")
        check(game.tiers[0].endsAt > Date(), "the first speed tier is still open")
        check(game.hints.letters == 2 && game.hints.brushes == 1 && game.hints.words == 1,
              "starting hint inventory is 2/1/1")
        check(game.hintPrices.letter == 10 && game.hintPrices.brush == 20 && game.hintPrices.word == 30,
              "default hint prices are 10/20/30")
        check(game.rejected.isEmpty, "a null rejectedWords decodes as empty")
        check(game.rows > 0 && game.columns > 0, "grid bounds derive from the cells")

        let fetched = try await client.game(campaignID: campaign.campaignId, level: 1)
        check(fetched.level == 1 && fetched.campaignId == campaign.campaignId, "GET level round-trips")

        // A word made only of queue letters that is not in the puzzle.
        let bogus = String(game.letters.prefix(3))
        let rejected = try await client.submitGuess(campaignID: campaign.campaignId, level: 1, word: bogus)
        check(["not_in_puzzle", "found", "already_found", "invalid_letters"].contains(rejected.outcome),
              "a guess returns a known outcome (\(rejected.outcome))")
        game = rejected.game

        let hint = try await client.useHint(campaignID: campaign.campaignId, level: 1, hint: .letter)
        check(hint.outcome.contains("reveal"), "a free letter hint reveals (\(hint.outcome))")
        check(hint.game.hints.letters == 1, "free letter hints decrement")
        check(hint.game.hintBonus < 10, "the hint bonus drops after a hint")
        check(hint.game.cells.contains { $0.hinted }, "a hinted cell is marked")
        check(hint.game.cells.first { $0.hinted }?.letter != nil, "a hinted cell carries its letter")
        game = hint.game

        // Brute-force the opening level so the completed-game contract (score,
        // solution words, the completion endpoint) is exercised for real.
        if game.letters.count <= 4 {
            for word in candidateWords(game.letters) where !game.complete {
                let result = try await client.submitGuess(
                    campaignID: campaign.campaignId, level: 1, word: word)
                game = result.game
            }
            check(game.complete, "the level completes once every word is found")
            check(game.foundWords == game.totalWords, "found words reach the total")
            check(game.cells.allSatisfy { $0.letter != nil }, "a completed grid exposes every letter")
            if let score = game.score {
                check(score.points >= 10, "a win awards at least 10 points (\(score.points))")
                check(score.points == score.basePoints + score.speedBonus + score.accuracyBonus + score.hintBonus,
                      "the score components sum to the total")
                check(score.durationSeconds >= 0, "the score carries a duration")
            } else {
                check(false, "a completed game carries a score")
            }

            let completion = try await client.completion(campaignID: campaign.campaignId)
            check(completion.player.activeGame == nil, "completion clears the active game")
            check(completion.player.completedLevelCount == 1, "completion records the level")
            check(completion.player.lifetimePointsEarned > 0, "completion awards lifetime points")
            check(completion.campaign?.completedLevels == 1, "the campaign card advances")
            check(completion.campaign?.levels.first { $0.status == .available }?.level == 2,
                  "level 2 becomes available")
        }

        let player = try await client.player()
        check(player.displayName == signUp.player.displayName, "GET /api/me matches the session player")

        let leaderboard = try await client.leaderboard()
        check(leaderboard.entries != nil, "leaderboard decodes")

        let link = try await client.playerWorkflowLink()
        check(link.absoluteString.contains("player%2F\(username)") || link.absoluteString.contains("player/\(username)"),
              "player workflow link resolves to the Temporal UI (\(link.absoluteString))")

        let levelLink = try await client.levelWorkflowLink(campaignID: campaign.campaignId, level: 1)
        check(levelLink.absoluteString.contains("wordflow-level"), "level workflow link resolves")

        check(await client.hasStoredSession(), "the session cookie is stored")
        try await client.logOut()
        check(!(await client.hasStoredSession()), "logout clears the session cookie")

        do {
            _ = try await client.openSession()
            check(false, "an unauthenticated session is rejected")
        } catch let error as APIError {
            check(error.isUnauthorized, "an unauthenticated session returns 401 (\(error.message))")
        }

        do {
            _ = try await client.logIn(username: username, password: "wrong-password-here")
            check(false, "a bad password is rejected")
        } catch let error as APIError {
            check(error.status == 401 && error.message.contains("Invalid"),
                  "a bad password returns the API error text (\(error.message))")
        }

        let back = try await client.logIn(username: username, password: "supersecret123")
        check(back.player.displayName == signUp.player.displayName, "log in restores the same player")
        check(back.game != nil || back.catalog != nil, "login returns either the active game or the catalog")
    } catch {
        Report.failures += 1
        print("  FAIL unexpected error: \(error)")
    }
}

await run()

print("\n\(Report.checks - Report.failures)/\(Report.checks) checks passed")
exit(Report.failures == 0 ? 0 : 1)
