import Foundation

/// A `/workflows/` page the app can open. The explorer is served by the
/// Wordflow API and authenticated with the same session cookie, so the URL is
/// always on the configured host.
struct WorkflowLink: Identifiable, Hashable, Sendable {
    var url: URL
    var title: String

    var id: URL { url }
}
