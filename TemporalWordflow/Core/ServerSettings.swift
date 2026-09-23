import Foundation

/// Where the app points its HTTP calls. The Wordflow API has no fixed public
/// host — the README runs it on `localhost:8080` — so the address is editable
/// and persisted instead of compiled in.
enum ServerSettings {
    static let defaultBaseURLString = "http://localhost:8080"
    private static let key = "wordflow.baseURL"

    static var storedBaseURLString: String {
        UserDefaults.standard.string(forKey: key) ?? defaultBaseURLString
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
