import Foundation
import Observation

/// Live tail of one workflow's history.
///
/// The explorer exposes whole pages rather than a "since event N" cursor, and
/// `GetWorkflowExecutionHistory` hands back an empty page token at the live
/// edge, so there is nothing to resume from. Instead each poll reads page one,
/// compares `historyLength` against what is already held, and only drains the
/// remaining pages when the workflow has actually moved.
@MainActor
@Observable
final class ExplorerFeed {
    private(set) var workflowID: String?
    private(set) var events: [ExplorerEvent] = []
    private(set) var summary: WorkflowSummary?
    private(set) var pending: PendingSummary?
    private(set) var lastUpdated: Date?
    private(set) var failure: String?
    private(set) var isLoading = false

    /// How often the kiosk explorer refreshes, matching the web kiosk view.
    static let pollInterval: Duration = .seconds(1)
    /// A runaway history should not be drained forever inside one tick.
    private static let maximumPages = 12

    private let api: APIClient
    private var pollTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    var isEmpty: Bool { events.isEmpty }

    var latestEventID: Int? { events.last?.id }

    /// Points the feed at a workflow and starts polling. Re-pointing resets the
    /// accumulated history so a new participant never inherits the last one's.
    func follow(workflowID: String) {
        guard self.workflowID != workflowID else {
            start()
            return
        }
        stop()
        self.workflowID = workflowID
        events = []
        summary = nil
        pending = nil
        lastUpdated = nil
        failure = nil
        start()
    }

    func start() {
        guard pollTask == nil, workflowID != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: ExplorerFeed.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func clear() {
        stop()
        workflowID = nil
        events = []
        summary = nil
        pending = nil
        lastUpdated = nil
        failure = nil
    }

    func refresh() async {
        guard let workflowID, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let first = try await api.workflowDetail(workflowID: workflowID)
            summary = first.workflow
            pending = first.pending
            lastUpdated = Date()
            failure = nil

            // Page one already covers the whole history until the workflow
            // outgrows a single page.
            guard first.workflow.historyLength > events.count else { return }

            var collected = first.events
            var token = first.nextPageToken
            var pages = 1
            while let next = token, !next.isEmpty, pages < Self.maximumPages {
                if Task.isCancelled { return }
                let page = try await api.workflowDetail(workflowID: workflowID, page: next)
                collected.append(contentsOf: page.events)
                token = page.nextPageToken
                pages += 1
            }
            events = collected
        } catch let error as APIError {
            failure = error.message
        } catch {
            failure = error.localizedDescription
        }
    }
}
