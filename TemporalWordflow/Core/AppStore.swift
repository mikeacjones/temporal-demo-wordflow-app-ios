import Foundation
import Observation

/// Mirrors the state machine in `internal/api/web/app.js`: the app owns only the
/// session cookie, the transient letter ordering, and the letters currently
/// selected on screen. Everything else is durable Temporal state read back from
/// the API on every mutation.
@MainActor
@Observable
final class AppStore {
    enum Phase: Equatable {
        case launching
        case authentication
        case catalog
        case game
        case complete
    }

    struct NextLevel: Equatable {
        var campaignID: String
        var level: Int
    }

    enum Busy: Hashable {
        case session
        case logIn
        case signUp
        case logOut
        case catalogRefresh
        case streakFreeze
        case campaign(String)
        case exitGame
        case continueLevel
        case guess
        case hint(HintKind)
        case workflowLink
    }

    // MARK: Durable state read from the API

    private(set) var player: Player?
    private(set) var campaigns: [Campaign] = []
    private(set) var hasCatalog = false
    private(set) var currentGame: Game?

    // MARK: Local presentation state

    /// The shuffled order the letter wheel is drawn in. Never sent to the server.
    private(set) var letterOrder: [Character] = []
    private(set) var selectedIndexes: [Int] = []
    private(set) var busy: Set<Busy> = []
    private(set) var notice: Notice?
    private(set) var reviewingCampaignID: String?
    /// The `/workflows/` page currently open over the app, if any.
    var presentedWorkflow: WorkflowLink?

    /// Completion screen bookkeeping, mirroring `beginCompletionRefresh`.
    private(set) var completionReady = false
    private(set) var continueTitle = "Checking next level…"
    private var completionAction: NextLevel?
    private var completionTask: Task<Void, Error>?
    private var deadlineRefreshTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var revalidationTask: Task<Void, Never>?
    private var refreshedBoundaries: Set<Date> = []

    private let api: APIClient
    private(set) var launching = true
    private(set) var baseURLString: String = ServerSettings.storedBaseURLString

    struct Notice: Equatable, Identifiable {
        var id = UUID()
        var message: String
        var isError: Bool
    }

    init(api: APIClient = .shared) {
        self.api = api
    }

    var phase: Phase {
        if launching { return .launching }
        guard player != nil else { return .authentication }
        if let game = currentGame { return game.isTerminal ? .complete : .game }
        return .catalog
    }

    var guess: String { String(selectedIndexes.map { letterOrder[$0] }) }

    func isBusy(_ key: Busy) -> Bool { busy.contains(key) }

    /// Any in-flight level mutation freezes the wheel and the hint row, matching
    /// `setGameControlsPending`.
    var gameMutationPending: Bool {
        busy.contains(.guess) || HintKind.allCases.contains { busy.contains(.hint($0)) }
    }

    var activeCampaign: Campaign? {
        guard let game = currentGame else { return nil }
        return campaigns.first { $0.campaignId == game.campaignId }
    }

    var isDailyGame: Bool { activeCampaign?.isDaily ?? false }

    var dailyChallenge: Campaign? {
        let daily = campaigns.filter(\.isDaily)
        if let active = daily.first(where: { $0.status == .active }) { return active }
        return daily
            .filter { $0.status == .upcoming }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            .first
    }

    var standardCampaigns: [Campaign] { campaigns.filter { !$0.isDaily } }

    // MARK: - Session

    func launch() async {
        launching = true
        await withBusy(.session) {
            do {
                let session = try await api.openSession()
                await adopt(session)
            } catch let error as APIError where error.isUnauthorized {
                reset()
            } catch {
                show(error: error)
                reset()
            }
        }
        launching = false
    }

    /// Every endpoint answers 401 when a Temporal query fails, not only when the
    /// cookie is bad — `queryPlayer` in server.go maps any query failure to
    /// "session is invalid or expired". So a 401 outside `/api/session` is
    /// re-checked against `/api/session` itself before the session is discarded;
    /// otherwise a worker restart would sign the player out mid-level.
    private func revalidateSession() {
        guard revalidationTask == nil, player != nil else { return }
        revalidationTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.api.openSession()
            } catch let error as APIError where error.isUnauthorized {
                self.reset()
                self.show(notice: "Your durable session expired. Log in to resume.", isError: true)
            } catch {
                // Still reachable, still signed in: leave the original message up.
            }
            self.revalidationTask = nil
        }
    }

    func logIn(username: String, password: String) async {
        await authenticate(.logIn) { try await self.api.logIn(username: username, password: password) }
    }

    func signUp(username: String, displayName: String, password: String,
                passwordConfirmation: String) async {
        await authenticate(.signUp) {
            try await self.api.signUp(
                username: username, displayName: displayName,
                password: password, passwordConfirmation: passwordConfirmation)
        }
    }

    private func authenticate(_ key: Busy, _ work: @escaping () async throws -> SessionResponse) async {
        await withBusy(key) {
            do {
                let session = try await work()
                await adopt(session)
                Haptics.success()
            } catch {
                show(error: error)
                Haptics.error()
            }
        }
    }

    func logOut() async {
        await withBusy(.logOut) {
            do { try await api.logOut() } catch { show(error: error) }
            reset()
        }
    }

    private func adopt(_ session: SessionResponse) async {
        player = session.player
        if session.player.activeGame != nil {
            await resumeGame(initial: session.game)
        } else {
            currentGame = nil
            await loadCatalog(initial: session.catalog)
        }
    }

    private func reset() {
        player = nil
        campaigns = []
        hasCatalog = false
        currentGame = nil
        letterOrder = []
        selectedIndexes = []
        reviewingCampaignID = nil
        completionTask?.cancel()
        completionTask = nil
        deadlineRefreshTask?.cancel()
        deadlineRefreshTask = nil
        revalidationTask?.cancel()
        revalidationTask = nil
        refreshedBoundaries = []
    }

    // MARK: - Catalog

    func loadCatalog(initial: CatalogResponse? = nil) async {
        currentGame = nil
        reviewingCampaignID = nil
        if let initial {
            campaigns = initial.campaigns
            hasCatalog = true
            return
        }
        await withBusy(.catalogRefresh) {
            do {
                campaigns = try await api.catalog().campaigns
                hasCatalog = true
            } catch {
                show(error: error)
            }
        }
    }

    /// Re-reads the catalog once when a countdown crosses its boundary, the way
    /// `startCampaignTicker` refreshes on a `now` tick.
    func catalogBoundaryReached(_ boundary: Date) {
        guard !refreshedBoundaries.contains(boundary) else { return }
        refreshedBoundaries.insert(boundary)
        Task { await refreshCatalogQuietly() }
    }

    func refreshCatalogQuietly() async {
        guard player != nil, currentGame == nil else { return }
        do {
            campaigns = try await api.catalog().campaigns
            hasCatalog = true
        } catch {
            // A pull-to-refresh is user-initiated, so its failure is worth a
            // toast; a background boundary refresh is not.
            if !isBusy(.catalogRefresh) { show(error: error) }
        }
    }

    func refreshPlayer() async {
        guard let refreshed = try? await api.player() else { return }
        player = refreshed
    }

    func buyStreakFreeze() async {
        await withBusy(.streakFreeze) {
            do {
                player = try await api.buyStreakFreeze()
                show(notice: "Streak freeze ready.")
                Haptics.success()
            } catch {
                show(error: error)
            }
        }
    }

    // MARK: - Levels

    func startLevel(campaignID: String, level: Int) async {
        await withBusy(.campaign(campaignID)) {
            do {
                let started = try await api.startLevel(campaignID: campaignID, level: level)
                player = started.player
                await resumeGame(initial: started.game)
                Haptics.tap()
            } catch {
                show(error: error)
            }
        }
    }

    func resumeActiveGame() async {
        guard let active = player?.activeGame else { return }
        await withBusy(.campaign(active.campaignId)) {
            await resumeGame(initial: nil)
        }
    }

    private func resumeGame(initial: Game?) async {
        if let initial {
            adopt(game: initial, reviewing: nil)
            return
        }
        guard let active = player?.activeGame else { return }
        do {
            let game = try await api.game(campaignID: active.campaignId, level: active.level)
            adopt(game: game, reviewing: nil)
        } catch {
            show(error: error)
        }
    }

    /// `reviewDailyOutcome` — reopens a finished daily attempt read-only.
    func reviewOutcome(for campaign: Campaign) async {
        let level = campaign.hasFailed ? campaign.nextLevel : campaign.totalLevels
        await withBusy(.campaign(campaign.campaignId)) {
            do {
                let game = try await api.game(campaignID: campaign.campaignId, level: level)
                adopt(game: game, reviewing: campaign.campaignId)
            } catch {
                show(error: error)
            }
        }
    }

    private func adopt(game: Game, reviewing: String?) {
        currentGame = game
        reviewingCampaignID = reviewing
        letterOrder = Self.shuffled(game.letters)
        selectedIndexes = []
        completionTask?.cancel()
        completionTask = nil
        completionAction = nil
        completionReady = false
        continueTitle = "Checking next level…"
        deadlineRefreshTask?.cancel()
        deadlineRefreshTask = nil
        if game.isTerminal { beginCompletionRefresh() }
    }

    func exitGame() async {
        await withBusy(.exitGame) {
            deadlineRefreshTask?.cancel()
            deadlineRefreshTask = nil
            completionTask?.cancel()
            completionTask = nil
            await loadCatalog()
        }
    }

    // MARK: - Letter wheel

    func select(index: Int) {
        guard !gameMutationPending, letterOrder.indices.contains(index) else { return }
        guard !selectedIndexes.contains(index) else { return }
        selectedIndexes.append(index)
        Haptics.letterTouched()
    }

    /// One token crossed by a swipe. Dragging back onto the previous letter
    /// removes the last one; a fresh touch-down cannot, so re-touching a token
    /// mid-word is inert, as a click is on the web.
    ///
    /// The gesture resolves each crossed token here rather than against the
    /// array it captured when the view was built, so a multi-sample frame still
    /// sees the selection it is building.
    func trace(index: Int, allowBacktrack: Bool) {
        guard !gameMutationPending, letterOrder.indices.contains(index) else { return }
        if allowBacktrack, selectedIndexes.count >= 2, selectedIndexes[selectedIndexes.count - 2] == index {
            selectedIndexes.removeLast()
            Haptics.letterTouched()
            return
        }
        guard !selectedIndexes.contains(index) else { return }
        selectedIndexes.append(index)
        Haptics.letterTouched()
    }

    /// A traced word submits when the finger lifts; a word tapped out one token
    /// at a time waits for the Submit button, as on the web.
    func submitTracedGuess() async {
        guard selectedIndexes.count >= 2 else { return }
        await submitGuess()
    }

    func clearGuess() {
        guard !selectedIndexes.isEmpty else { return }
        selectedIndexes = []
    }

    func shuffleLetters() {
        guard let game = currentGame else { return }
        letterOrder = Self.shuffled(game.letters, previous: letterOrder)
        selectedIndexes = []
        Haptics.tap()
    }

    /// `shuffledLetters` in app.js: retry a few times so a shuffle visibly moves.
    static func shuffled(_ letters: String, previous: [Character] = []) -> [Character] {
        var shuffled = Array(letters)
        for _ in 0..<4 {
            shuffled = Array(letters).shuffled()
            if shuffled != previous { break }
        }
        return shuffled
    }

    // MARK: - Gameplay mutations

    func submitGuess() async {
        guard let game = currentGame, !guess.isEmpty, !gameMutationPending else { return }
        let word = guess
        await withBusy(.guess) {
            do {
                let result = try await api.submitGuess(
                    campaignID: game.campaignId, level: game.level, word: word)
                let previouslyFound = currentGame?.foundWords ?? 0
                apply(game: result.game)
                selectedIndexes = []
                show(notice: GuessOutcome.notice(for: result.outcome),
                     isError: result.outcome != GuessOutcome.found.rawValue)
                if result.game.foundWords > previouslyFound {
                    Haptics.success()
                } else {
                    Haptics.warning()
                }
            } catch {
                show(error: error)
                Haptics.error()
            }
        }
    }

    func useHint(_ hint: HintKind) async {
        guard let game = currentGame, !gameMutationPending else { return }
        let buying = hint.remaining(in: game.hints) == 0
        await withBusy(.hint(hint)) {
            do {
                let result = try await api.useHint(
                    campaignID: game.campaignId, level: game.level, hint: hint)
                apply(game: result.game)
                selectedIndexes = []
                if let remaining = result.pointsRemaining {
                    player?.points = remaining
                }
                let outcome = result.outcome.replacingOccurrences(of: "_", with: " ")
                if let spent = result.pointsSpent, spent > 0 {
                    show(notice: "Spent \(spent) points · \(outcome)")
                } else {
                    show(notice: outcome)
                }
                Haptics.tap()
            } catch {
                show(error: error)
                Haptics.error()
                // A rejected purchase may still have moved the balance; re-read it
                // without clobbering the error the player is looking at.
                if buying { await refreshPlayer() }
            }
        }
    }

    private func apply(game: Game) {
        let wasTerminal = currentGame?.isTerminal ?? false
        currentGame = game
        if game.isTerminal && !wasTerminal {
            beginCompletionRefresh()
        }
    }

    // MARK: - Hard time limit

    /// `refreshExpiredLevel`: the level Workflow closes itself when its timer
    /// fires, so poll briefly until the timed-out view appears.
    func levelDeadlinePassed() {
        guard deadlineRefreshTask == nil, let game = currentGame, !game.isTerminal else { return }
        let campaignID = game.campaignId
        let level = game.level
        deadlineRefreshTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                guard let latest = try? await self.api.game(campaignID: campaignID, level: level) else { continue }
                if latest.didTimeOut {
                    if self.currentGame?.campaignId == campaignID, self.currentGame?.level == level {
                        self.apply(game: latest)
                    }
                    self.deadlineRefreshTask = nil
                    return
                }
            }
            self.deadlineRefreshTask = nil
            self.show(notice: "The level timer expired, but its Workflow has not closed yet.", isError: true)
        }
    }

    // MARK: - Completion

    private func beginCompletionRefresh() {
        guard completionTask == nil else { return }
        completionReady = false
        continueTitle = "Checking next level…"
        completionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.prepareCompletionAction()
                self.completionReady = true
            } catch {
                self.completionTask = nil
                self.completionReady = true
                self.continueTitle = "Try again"
                self.show(error: error)
                throw error
            }
        }
    }

    private func prepareCompletionAction() async throws {
        guard let game = currentGame else { return }
        let campaignID = game.campaignId
        let completion = try await api.completion(campaignID: campaignID)
        player = completion.player

        var updated = campaigns
        if let campaign = completion.campaign {
            if let index = updated.firstIndex(where: { $0.campaignId == campaignID }) {
                updated[index] = campaign
            } else {
                updated.append(campaign)
            }
        } else {
            updated.removeAll { $0.campaignId == campaignID }
        }
        campaigns = updated
        hasCatalog = true

        let next = completion.campaign?.levels.first { $0.status == .available }
        if let next, let campaign = completion.campaign {
            completionAction = NextLevel(campaignID: campaign.campaignId, level: next.level)
            continueTitle = "Play level \(next.level)"
        } else {
            completionAction = nil
            continueTitle = "Back to campaigns"
        }
    }

    func continueFromCompletion() async {
        await withBusy(.continueLevel) {
            if completionTask == nil, player?.activeGame != nil {
                beginCompletionRefresh()
            }
            if let task = completionTask {
                do {
                    try await task.value
                } catch {
                    // app.js lets this rejection escape `showNextWordflow`, which
                    // keeps the completion screen — and its retry — on screen.
                    completionTask = nil
                    return
                }
            }
            completionTask = nil
            if let next = completionAction {
                completionAction = nil
                await startLevel(campaignID: next.campaignID, level: next.level)
                return
            }
            await loadCatalog(initial: CatalogResponse(campaigns: campaigns))
        }
    }

    // MARK: - Leaderboard

    /// The standalone leaderboard page polls this every three seconds. It goes
    /// through the store so it uses the same client — and therefore the same
    /// server address — as everything else.
    func leaderboard() async throws -> [LeaderboardEntry] {
        try await api.leaderboard().entries ?? []
    }

    // MARK: - Temporal Web UI links

    func openPlayerWorkflow() async {
        guard let url = await workflowURL({ try await self.api.playerWorkflowLink() }) else { return }
        presentedWorkflow = WorkflowLink(url: url, title: "Player Workflow")
    }

    func openLevelWorkflow() async {
        guard let game = currentGame else { return }
        let url = await workflowURL {
            try await self.api.levelWorkflowLink(campaignID: game.campaignId, level: game.level)
        }
        guard let url else { return }
        presentedWorkflow = WorkflowLink(url: url, title: "Level \(game.level) Workflow")
    }

    /// `catalogCampaignResponse.workflowUrl` is a path on the API host, so it is
    /// resolved against the configured base URL rather than opened as given.
    func openCampaignWorkflow(_ campaign: Campaign) {
        guard let url = URL(string: campaign.workflowUrl, relativeTo: api.baseURLValue)?.absoluteURL else {
            show(notice: "That workflow link is not valid.", isError: true)
            return
        }
        presentedWorkflow = WorkflowLink(url: url, title: campaign.title)
    }

    func dismissWorkflow() {
        presentedWorkflow = nil
    }

    private func workflowURL(_ work: @escaping () async throws -> URL) async -> URL? {
        busy.insert(.workflowLink)
        defer { busy.remove(.workflowLink) }
        do {
            return try await work()
        } catch {
            show(error: error)
            return nil
        }
    }

    // MARK: - Server address

    func updateBaseURL(_ raw: String) -> Bool {
        guard let url = ServerSettings.normalize(raw) else {
            show(notice: "That server address is not valid.", isError: true)
            return false
        }
        ServerSettings.store(url.absoluteString)
        baseURLString = url.absoluteString
        Task {
            await api.setBaseURL(url)
            reset()
            await launch()
        }
        return true
    }

    // MARK: - Notices

    func show(notice message: String, isError: Bool = false) {
        notice = Notice(message: message, isError: isError)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func dismissNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    private func show(error: Error) {
        show(notice: error.localizedDescription, isError: true)
        if let apiError = error as? APIError, apiError.isUnauthorized {
            revalidateSession()
        }
    }

    private func withBusy(_ key: Busy, _ work: () async -> Void) async {
        guard !busy.contains(key) else { return }
        busy.insert(key)
        await work()
        busy.remove(key)
    }
}
