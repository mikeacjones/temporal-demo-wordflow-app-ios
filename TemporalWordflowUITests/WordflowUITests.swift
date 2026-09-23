import XCTest

/// End-to-end tests against a running Wordflow server.
///
/// These are the only checks that exercise the parts a macOS compile cannot:
/// the drag recogniser on the letter dial, real hit testing, and the navigation
/// between phases. They need the API on the address the app defaults to:
///
///     cd ../temporal-word-game
///     TEMPORAL_NAMESPACE=iostest go run ./cmd/worker
///     TEMPORAL_NAMESPACE=iostest HTTP_ADDRESS=:8080 \
///       SESSION_JWT_SECRET=local-temporal-wordflow-jwt-secret-change-before-deploying \
///       go run ./cmd/server
final class WordflowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        // iOS offers to save the credential after a successful sign-in. The
        // alert is presented out of process, sits over the app and swallows
        // every gesture until it is answered.
        addUIInterruptionMonitor(withDescription: "AutoFill") { alert in
            for label in Self.dismissLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app = XCUIApplication()
        app.launch()
    }

    private static let dismissLabels = ["Not Now", "Not now", "Close", "Cancel"]
    private static let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    // MARK: - Tests

    /// Sign up, open level 1, and tap out FLOW one letter at a time.
    func testTappingOutAWordRecordsIt() {
        signInAsNewPlayer()
        startFirstCampaign()

        for character in "FLOW" {
            tap(letter(character), "letter \(character)")
        }
        XCTAssertTrue(app.staticTexts["Current word FLOW"].waitForExistence(timeout: 5),
                      "tapping four letters should build the word")

        tap(app.buttons["Submit word"].firstMatch, "Submit word")

        XCTAssertTrue(app.staticTexts["Word recorded in history."].waitForExistence(timeout: 20),
                      "a correct word should raise the web's notice copy")
        XCTAssertTrue(app.staticTexts["1 / 4 words resolved"].waitForExistence(timeout: 20),
                      "the durable progress should come back updated")
        XCTAssertTrue(app.staticTexts["No letters selected"].waitForExistence(timeout: 5),
                      "submitting should clear the selection")
    }

    /// Trace two letters with one continuous drag: the word must submit itself
    /// when the finger lifts, which is the whole point of the native port.
    func testSwipingTwoLettersSubmitsOnLift() {
        signInAsNewPlayer()
        startFirstCampaign()

        // The dial is shuffled, so pick two tokens a quarter-turn apart by
        // position rather than by letter: their chord clears the hub and passes
        // no other token.
        // The dial sits below the fold on the game screen, and a coordinate
        // drag whose path leaves the visible area is cut short — so the whole
        // dial, not just its top edge, has to be scrolled in.
        guard scrollIntoView(app.descendants(matching: .any)["Available letters"].firstMatch,
                             "letter dial") else { return }
        var extra = 0
        while !letterTokens().allSatisfy(\.isHittable) && extra < 8 {
            drag(dy: -0.2)
            extra += 1
        }

        let tokens = letterTokens()
        XCTAssertEqual(tokens.count, 4, "level 1 has a four-letter queue")
        XCTAssertTrue(tokens.allSatisfy(\.isHittable), "every token should be on screen to trace across")
        // Two tokens a quarter-turn apart: their chord clears the hub and
        // passes no other token.
        let ordered = tokens.sorted { $0.frame.midY < $1.frame.midY }
        let top = ordered[0]
        let side = ordered[1]

        top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: side.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: .slow,
                   thenHoldForDuration: 0.2)

        // Whatever two letters those were, the guess goes to the server on lift
        // and comes back as one of the four outcomes in app.js's notice map.
        let outcomes = ["Word recorded in history.", "Already in history.",
                        "Not in the wordflow.", "Those letters cannot make that word."]
        let notice = outcomes.map { app.staticTexts[$0] }
        XCTAssertTrue(waitForAny(notice, timeout: 20),
                      "lifting a traced word should submit it without pressing Submit")
        XCTAssertTrue(app.staticTexts["No letters selected"].waitForExistence(timeout: 10),
                      "the wheel should be clear again afterwards")
    }

    /// The sign-up form, including the confirmation field the API started
    /// requiring in `Require password confirmation on signup`.
    func testSigningUpRequiresAMatchingConfirmation() {
        signOutIfNeeded()
        tap(app.buttons["Sign up"], "Sign up tab")

        let username = "ui\(String(UUID().uuidString.prefix(8)).lowercased())"
        type(username, into: "Username")
        type("UI Test", into: "Display name")
        typeSecret(Self.password, into: "Password")
        typeSecret("not-the-same-123", into: "Confirm password")

        XCTAssertTrue(app.staticTexts["Passwords do not match."].waitForExistence(timeout: 5),
                      "a mismatched confirmation should be reported in the form")
        XCTAssertFalse(app.buttons["Create account"].isEnabled,
                       "a mismatched confirmation should block submission")

        let confirmation = app.secureTextFields["Confirm password"]
        confirmation.tap()
        dismissSystemPasswordAlert(waiting: 3)
        confirmation.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24))
        confirmation.typeText(Self.password)
        XCTAssertFalse(app.staticTexts["Passwords do not match."].exists,
                       "a matching confirmation should clear the message")

        tap(app.buttons["Create account"], "Create account")
        dismissSystemPasswordAlert(waiting: 10)
        XCTAssertTrue(app.staticTexts["Campaigns"].waitForExistence(timeout: 60),
                      "signing up should land on the campaign browser")
        dismissSystemPasswordAlert(waiting: 5)
    }

    /// `/workflows/` is authenticated with the same cookie as the API, so the
    /// in-app web view has to carry it or the explorer treats the viewer as
    /// anonymous.
    func testWorkflowLinkOpensTheExplorerSignedIn() {
        let username = signInAsNewPlayer()
        tap(app.buttons["Campaign Workflow ↗"], "Campaign Workflow link")

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 30),
                      "the workflow sheet should open in-app")
        XCTAssertTrue(app.webViews.staticTexts["Private view · \(username)"].waitForExistence(timeout: 60),
                      "the explorer should see the app's session cookie")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Campaigns"].waitForExistence(timeout: 20),
                      "dismissing the sheet should return to the catalog")
    }

    /// Leaving a level returns to the catalog with the level still resumable,
    /// which is the contract the Player Workflow keeps.
    func testLeavingALevelKeepsItResumable() {
        signInAsNewPlayer()
        startFirstCampaign()

        tap(app.buttons["Campaigns"].firstMatch, "Campaigns")
        tap(app.buttons["Resume level 1"], "Resume level 1")
        XCTAssertTrue(app.staticTexts["0 / 4 words resolved"].waitForExistence(timeout: 60),
                      "resuming should reopen the same level")
    }


    // MARK: - Helpers

    /// Registers a throwaway player over HTTP and signs into it through the
    /// log-in form. Creating the account out of band keeps the gameplay tests
    /// off the sign-up form, whose `.newPassword` field makes iOS put its
    /// "Use Strong Password?" sheet over the keyboard.
    @discardableResult
    private func signInAsNewPlayer() -> String {
        let username = "ui\(String(UUID().uuidString.prefix(8)).lowercased())"
        registerOverHTTP(username: username)
        signOutIfNeeded()
        type(username, into: "Username")
        // The form submits from the keyboard's Go key, which is what a player
        // does and what keeps the submit button from hiding behind it.
        type(Self.password + "\n", into: "Password")
        dismissSystemPasswordAlert(waiting: 10)

        XCTAssertTrue(app.staticTexts["Campaigns"].waitForExistence(timeout: 60),
                      "logging in should land on the campaign browser")
        dismissSystemPasswordAlert(waiting: 5)
        return username
    }

    /// The session cookie survives between test cases, so a run can start on
    /// the catalog rather than the sign-in form.
    private func signOutIfNeeded() {
        let signUpTab = app.buttons["Sign up"]
        let settings = app.buttons["Settings"]
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if signUpTab.exists { return }
            if settings.exists {
                settings.tap()
                tap(app.buttons["Log out"].firstMatch, "Log out")
                XCTAssertTrue(signUpTab.waitForExistence(timeout: 30),
                              "logging out should return to the sign-in form")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("the app never settled into a signed-in or signed-out state")
    }

    private static let password = "supersecret123"
    private static let baseURL = URL(string: ProcessInfo.processInfo
        .environment["WORDFLOW_BASE_URL"] ?? "http://localhost:8080")!

    private func registerOverHTTP(username: String) {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/signup"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "username": username,
            "displayName": "UI Test",
            "password": Self.password,
            "passwordConfirmation": Self.password,
            "requestId": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
        ])
        let done = expectation(description: "register \(username)")
        var status = 0
        URLSession(configuration: .ephemeral).dataTask(with: request) { _, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 60)
        XCTAssertEqual(status, 201,
                       "the Wordflow API must be reachable at \(Self.baseURL.absoluteString)")
    }

    private func startFirstCampaign() {
        tap(app.buttons["Start campaign"], "Start campaign")
        XCTAssertTrue(app.staticTexts["0 / 4 words resolved"].waitForExistence(timeout: 60),
                      "level 1 should open with no words resolved")
    }

    /// The catalog is taller than the screen, and `tap()` on an element that is
    /// off-screen lands on empty space rather than scrolling to it.
    private func tap(_ element: XCUIElement, _ name: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 30), "\(name) should exist")
        // A visible control can still be unhittable behind the keyboard, and
        // `.scrollDismissesKeyboard(.interactively)` clears it on a downward drag.
        if app.keyboards.element.exists { drag(dy: 0.35) }

        guard scrollIntoView(element, name) else { return }
        element.tap()
    }

    @discardableResult
    private func scrollIntoView(_ element: XCUIElement, _ name: String) -> Bool {
        var scrolls = 0
        var trace = [element.frame.midY]
        while !element.isHittable && scrolls < 14 {
            drag(dy: -0.55)
            scrolls += 1
            trace.append(element.frame.midY)
        }
        guard element.isHittable else {
            XCTFail("\(name) never became reachable after \(scrolls) scrolls; "
                    + "midY went \(trace.map { Int($0) }) in window \(app.windows.firstMatch.frame)")
            return false
        }
        return true
    }

    /// The AutoFill alert can be owned by the app, by SpringBoard or by the
    /// credential service depending on the iOS build, so every source is tried
    /// before falling back to the interruption monitor.
    @discardableResult
    private func dismissSystemPasswordAlert(waiting timeout: TimeInterval = 0) -> Bool {
        // Only apps that are actually running: querying a bundle that is not
        // launched costs a multi-second timeout per lookup.
        let owners = [app!, Self.springboard]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for owner in owners {
                for label in Self.dismissLabels {
                    let button = owner.alerts.buttons[label].exists
                        ? owner.alerts.buttons[label]
                        : owner.buttons[label]
                    if button.exists {
                        button.tap()
                        return true
                    }
                }
            }
            if Date() >= deadline { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        } while Date() < deadline
        return false
    }

    /// A raw drag on the window, which scrolls whatever is under it regardless
    /// of how the scroll view resolves in the element tree.
    private func drag(dy: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = start.withOffset(CGVector(dx: 0, dy: app.frame.height * dy))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default,
                    thenHoldForDuration: 0.05)
    }

    /// A `.newPassword` field brings up the "Use Strong Password?" sheet as soon
    /// as it takes focus, and the sheet covers the keyboard.
    private func typeSecret(_ text: String, into label: String) {
        let field = app.secureTextFields[label]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(label) field should exist")
        field.tap()
        dismissSystemPasswordAlert(waiting: 3)
        if !field.isHittable { drag(dy: 0.3) }
        field.tap()
        field.typeText(text)
    }

    private func type(_ text: String, into label: String) {
        let plain = app.textFields[label]
        let field = plain.waitForExistence(timeout: 10) ? plain : app.secureTextFields[label]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(label) field should exist")
        field.tap()
        field.typeText(text)
    }

    private func letter(_ character: Character) -> XCUIElement {
        let element = app.descendants(matching: .any)["Letter \(character)"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 20), "token \(character) should be on the dial")
        return element
    }

    private func letterTokens() -> [XCUIElement] {
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Letter "))
        _ = matches.firstMatch.waitForExistence(timeout: 20)
        return matches.allElementsBoundByIndex.filter { $0.frame.width > 0 }
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: \.exists) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return false
    }
}
