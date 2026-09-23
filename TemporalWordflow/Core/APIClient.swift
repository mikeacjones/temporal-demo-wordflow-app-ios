import Foundation

/// Error surfaced by the Wordflow HTTP API. `message` is the `{"error": ...}`
/// body the Go handlers write, so it can be shown verbatim in a notice.
struct APIError: LocalizedError, Sendable {
    var status: Int
    var message: String

    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }

    static func transport(_ error: Error) -> APIError {
        APIError(status: 0, message: friendlyTransportMessage(error))
    }

    private static func friendlyTransportMessage(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return error.localizedDescription }
        switch nsError.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return "Cannot reach the Wordflow server. Check the server address in Settings."
        case NSURLErrorNotConnectedToInternet:
            return "No network connection."
        case NSURLErrorTimedOut:
            return "The Wordflow server did not respond in time."
        default:
            return nsError.localizedDescription
        }
    }
}

/// Stops URLSession from following the 302 that `/workflow-link` returns so the
/// Temporal UI destination can be opened in the browser instead.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let noRedirect = NoRedirectDelegate()

    /// Mutated only through `setBaseURL`. The actor owns it; `baseURLValue`
    /// exposes the last value synchronously for link resolution on the main
    /// actor, which is why the setter updates both.
    private var baseURL: URL
    nonisolated(unsafe) private(set) var baseURLValue: URL

    init(baseURL: URL = ServerSettings.storedBaseURL) {
        self.baseURL = baseURL
        self.baseURLValue = baseURL

        let configuration = URLSessionConfiguration.default
        // The API authenticates with the HttpOnly `wordflow_session` cookie, so the
        // shared persistent cookie jar is what keeps the player signed in between
        // launches. No token is ever handled by the app itself.
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = GoTimestamp.parse(value) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unrecognised timestamp \(value)"))
            }
            return date
        }
        encoder = JSONEncoder()
    }

    func setBaseURL(_ url: URL) {
        baseURL = url
        baseURLValue = url
    }

    func currentBaseURL() -> URL { baseURL }

    // MARK: - Session

    func openSession() async throws -> SessionResponse {
        try await get("api/session")
    }

    func logIn(username: String, password: String) async throws -> SessionResponse {
        try await post("api/login", body: LoginBody(
            username: username, password: password, requestId: Self.requestID()))
    }

    func signUp(username: String, displayName: String, password: String,
                passwordConfirmation: String) async throws -> SessionResponse {
        try await post("api/signup", body: SignUpBody(
            username: username, displayName: displayName,
            password: password, passwordConfirmation: passwordConfirmation,
            requestId: Self.requestID()))
    }

    func logOut() async throws {
        let _: SignedOutResponse = try await request("api/session", method: "DELETE", body: nil as EmptyBody?)
        clearCookies()
    }

    // MARK: - Player

    func player() async throws -> Player {
        try await get("api/me")
    }

    func buyStreakFreeze() async throws -> Player {
        try await post("api/me/streak-freeze", body: RequestIDBody(requestId: Self.requestID()))
    }

    // MARK: - Catalog and games

    func catalog() async throws -> CatalogResponse {
        try await get("api/catalog")
    }

    func completion(campaignID: String) async throws -> CompletionResponse {
        try await get("api/me/campaigns/\(escape(campaignID))/completion")
    }

    func startLevel(campaignID: String, level: Int) async throws -> StartGameResponse {
        try await post("api/me/campaigns/\(escape(campaignID))/levels",
                       body: StartLevelBody(requestId: Self.requestID(), level: level))
    }

    func game(campaignID: String, level: Int) async throws -> Game {
        try await get("api/me/campaigns/\(escape(campaignID))/levels/\(level)")
    }

    func submitGuess(campaignID: String, level: Int, word: String) async throws -> GuessResponse {
        try await post("api/me/campaigns/\(escape(campaignID))/levels/\(level)/guesses",
                       body: GuessBody(requestId: Self.requestID(), word: word))
    }

    func useHint(campaignID: String, level: Int, hint: HintKind) async throws -> HintResponse {
        try await post("api/me/campaigns/\(escape(campaignID))/levels/\(level)/hints",
                       body: HintBody(requestId: Self.requestID(), hint: hint.rawValue))
    }

    func leaderboard() async throws -> LeaderboardResponse {
        try await get("api/leaderboard")
    }

    // MARK: - Temporal UI links

    /// Resolves the `Location` of a `/workflow-link` redirect without following
    /// it, so the Temporal Web UI can be opened outside the authenticated session.
    func workflowLink(path: String) async throws -> URL {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request, delegate: noRedirect)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "Unexpected response")
        }
        guard (300..<400).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: baseURL)?.absoluteURL
        else {
            throw APIError(status: http.statusCode, message: "No workflow link available")
        }
        return url
    }

    func playerWorkflowLink() async throws -> URL {
        try await workflowLink(path: "api/me/workflow-link")
    }

    func levelWorkflowLink(campaignID: String, level: Int) async throws -> URL {
        try await workflowLink(path: "api/me/campaigns/\(escape(campaignID))/levels/\(level)/workflow-link")
    }

    // MARK: - Cookies

    func clearCookies() {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) else { return }
        for cookie in cookies { HTTPCookieStorage.shared.deleteCookie(cookie) }
    }

    /// True when a session cookie for the current host is still stored, which lets
    /// the launch screen pick between the sign-in form and a restore attempt.
    func hasStoredSession() -> Bool {
        HTTPCookieStorage.shared.cookies(for: baseURL)?
            .contains { $0.name == "wordflow_session" && !$0.value.isEmpty } ?? false
    }

    // MARK: - Transport

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        try await request(path, method: "GET", body: nil as EmptyBody?)
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await request(path, method: "POST", body: body)
    }

    private func request<Body: Encodable, Response: Decodable>(
        _ path: String, method: String, body: Body?
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "Unexpected response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(APIErrorBody.self, from: data))?.error
            throw APIError(status: http.statusCode, message: message ?? "Request failed")
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError(status: http.statusCode, message: "Could not read the server response.")
        }
    }

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    /// The API reuses the request ID as the Temporal Update ID, which is how a
    /// retried mutation is deduplicated server side.
    private static func requestID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

// MARK: - Request bodies
//
// The API decodes with `DisallowUnknownFields`, so each body carries exactly the
// fields its handler declares.

private struct EmptyBody: Encodable {}

private struct LoginBody: Encodable {
    var username: String
    var password: String
    var requestId: String
}

private struct SignUpBody: Encodable {
    var username: String
    var displayName: String
    var password: String
    var passwordConfirmation: String
    var requestId: String
}

private struct RequestIDBody: Encodable {
    var requestId: String
}

private struct StartLevelBody: Encodable {
    var requestId: String
    var level: Int
}

private struct GuessBody: Encodable {
    var requestId: String
    var word: String
}

private struct HintBody: Encodable {
    var requestId: String
    var hint: String
}
