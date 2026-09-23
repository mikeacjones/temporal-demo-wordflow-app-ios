import Foundation

/// Where the app points its HTTP calls. It ships pointed at the hosted demo,
/// and the address stays editable so the same build can run against a local
/// `make server` or any other deployment.
enum ServerSettings {
    static let defaultBaseURLString = "https://games.tmprl-demo.cloud"

    /// Overrides everything, so the UI tests and the scripts in Tools/ can aim
    /// the shipping code at a throwaway server without touching what the player
    /// has saved. Never set in a normal launch.
    static let overrideEnvironmentKey = "WORDFLOW_BASE_URL"

    private static let key = "wordflow.baseURL"

    static var storedBaseURLString: String {
        if let override = ProcessInfo.processInfo.environment[overrideEnvironmentKey],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return UserDefaults.standard.string(forKey: key) ?? defaultBaseURLString
    }

    static var storedBaseURL: URL {
        normalize(storedBaseURLString) ?? URL(string: defaultBaseURLString)!
    }

    static func store(_ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Accepts `host`, `host:8080`, or a full URL and returns a usable base URL.
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
