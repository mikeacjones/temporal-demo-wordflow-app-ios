import Foundation

// Codable mirrors of the read-only Workflow Explorer served at /workflows/
// (internal/explorer/server.go). The same session cookie authorises it, and it
// only ever returns workflows the signed-in player owns plus the public ones.

struct WorkflowSummary: Codable, Hashable, Sendable {
    var workflowId: String
    var runId: String
    var type: String
    var kind: String
    var visibility: String
    var status: String
    var startedAt: Date?
    var closedAt: Date?
    var historyLength: Int
    var historySizeBytes: Int
    var stateTransitionCount: Int
    var versioningBehavior: String?
    var workerDeployment: String?
    var workerBuildId: String?
    var hasParent: Bool

    var isRunning: Bool { status == "running" }
}

struct PendingSummary: Codable, Hashable, Sendable {
    var activities: Int
    var children: Int
    var nexus: Int

    var total: Int { activities + children + nexus }
}

struct WorkflowReference: Codable, Hashable, Sendable {
    var workflowId: String
    var runId: String
    var type: String
    var kind: String
}

/// `eventCategory` in the explorer buckets every history event into one of
/// these, which is what drives the colour of the number chip.
enum EventCategory: String, Codable, Sendable {
    case lifecycle, worker, activity, timer, child, message, nexus, state
}

struct ExplorerEvent: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var time: Date?
    var type: String
    var category: EventCategory
    var title: String
    var detail: String?
    var details: JSONValue?
    var childWorkflow: WorkflowReference?
}

struct WorkflowDetail: Codable, Sendable {
    var workflow: WorkflowSummary
    var pending: PendingSummary
    var events: [ExplorerEvent]
    var nextPageToken: String?
}

/// Event payloads are free-form JSON, so they are decoded structurally and
/// re-rendered rather than mapped onto a fixed shape.
enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var isEmpty: Bool {
        switch self {
        case .object(let value): value.isEmpty
        case .array(let value): value.isEmpty
        case .null: true
        default: false
        }
    }

    /// Indented text for the payload pane, with object keys in a stable order
    /// so a one-second poll does not reshuffle the lines.
    func prettyPrinted(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)
        switch self {
        case .string(let value): return "\"\(value)\""
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15
                ? String(Int(value))
                : String(value)
        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            let body = values.map { inner + $0.prettyPrinted(indent: indent + 1) }
            return "[\n" + body.joined(separator: ",\n") + "\n" + pad + "]"
        case .object(let values):
            guard !values.isEmpty else { return "{}" }
            let body = values.keys.sorted().map { key in
                inner + "\"\(key)\": " + values[key]!.prettyPrinted(indent: indent + 1)
            }
            return "{\n" + body.joined(separator: ",\n") + "\n" + pad + "}"
        }
    }
}

// MARK: - Kiosk

/// `GET /api/kiosk/status` — 404 when the server is not running an event
/// station, which is how the app decides whether kiosk mode is available.
struct KioskStatus: Codable, Sendable {
    var active: Bool
    var workflowUrl: String?

    /// `workflowUrl` is `/workflows/?workflowId=player%2F…&kiosk=1`; the feed
    /// needs the bare ID.
    var workflowID: String? {
        guard let workflowUrl,
              let components = URLComponents(string: workflowUrl),
              let value = components.queryItems?.first(where: { $0.name == "workflowId" })?.value
        else { return nil }
        return value
    }
}
