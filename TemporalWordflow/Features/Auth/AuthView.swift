// Ports the #auth section (both .auth-card forms) and the #startup .app-loading card of web/index.html.

import Foundation
import SwiftUI

struct AuthView: View {
    @Binding var showingSettings: Bool

    @Environment(AppStore.self) private var store

    @State private var tab: AuthTab = .logIn
    @State private var loginUsername = ""
    @State private var loginPassword = ""
    @State private var signUpUsername = ""
    @State private var signUpDisplayName = ""
    @State private var signUpPassword = ""
    @State private var signUpConfirmation = ""
    @State private var touched: Set<AuthField> = []
    @FocusState private var focused: AuthField?

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 18) {
                AuthTabPicker(selection: $tab)
                switch tab {
                case .logIn: logInCard
                case .signUp: signUpCard
                }
                serverFooter
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .interactiveDismissKeyboard()
        .onChange(of: tab) { focused = nil }
        .onChange(of: focused) { previous, _ in
            if let previous { touched.insert(previous) }
        }
    }

    // MARK: - Log in

    private var logInCard: some View {
        NeoPanel(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Resume state")
                    .padding(.bottom, 7)
                DisplayTitle(text: "Log in", size: 24)

                AuthTextField(label: "Username", problem: problem(for: .logInUsername)) {
                    TextField("", text: $loginUsername)
                        .usernameField()
                        .focused($focused, equals: .logInUsername)
                        .submitLabel(.next)
                        .onSubmit { focused = .logInPassword }
                }
                AuthTextField(label: "Password", problem: problem(for: .logInPassword)) {
                    SecureField("", text: $loginPassword)
                        .passwordField(isNew: false)
                        .focused($focused, equals: .logInPassword)
                        .submitLabel(.go)
                        .onSubmit(submitLogIn)
                }

                PendingButton(
                    title: "Log in",
                    busyTitle: "Logging in…",
                    style: PrimaryButtonStyle(),
                    isBusy: store.isBusy(.logIn),
                    isEnabled: canLogIn,
                    action: submitLogIn)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Sign up

    private var signUpCard: some View {
        NeoPanel(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Start durable state")
                    .padding(.bottom, 7)
                DisplayTitle(text: "Sign up", size: 24)

                AuthTextField(label: "Username", problem: problem(for: .signUpUsername)) {
                    TextField("", text: $signUpUsername)
                        .usernameField()
                        .focused($focused, equals: .signUpUsername)
                        .submitLabel(.next)
                        .onSubmit { focused = .signUpDisplayName }
                }
                AuthTextField(label: "Display name", problem: problem(for: .signUpDisplayName)) {
                    TextField("", text: $signUpDisplayName)
                        .displayNameField()
                        .focused($focused, equals: .signUpDisplayName)
                        .submitLabel(.next)
                        .onSubmit { focused = .signUpPassword }
                }
                AuthTextField(label: "Password", problem: problem(for: .signUpPassword)) {
                    SecureField("", text: $signUpPassword)
                        .passwordField(isNew: true)
                        .focused($focused, equals: .signUpPassword)
                        .submitLabel(.next)
                        .onSubmit { focused = .signUpConfirmation }
                }
                AuthTextField(label: "Confirm password", problem: problem(for: .signUpConfirmation)) {
                    SecureField("", text: $signUpConfirmation)
                        .passwordField(isNew: true)
                        .focused($focused, equals: .signUpConfirmation)
                        .submitLabel(.go)
                        .onSubmit(submitSignUp)
                }

                PendingButton(
                    title: "Create account",
                    busyTitle: "Creating account…",
                    style: PrimaryButtonStyle(),
                    isBusy: store.isBusy(.signUp),
                    isEnabled: canSignUp,
                    action: submitSignUp)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Server footer

    private var serverFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: "Server", color: Palette.muted)
                Text(store.baseURLString)
                    .font(Typography.mono(12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("Change") { showingSettings = true }
                .buttonStyle(QuietButtonStyle(compact: true))
                .accessibilityLabel("Change server address")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Validation

    private var logInProblems: [AuthField: String] {
        var problems: [AuthField: String] = [:]
        problems[.logInUsername] = AuthRules.username(loginUsername)
        problems[.logInPassword] = AuthRules.password(loginPassword)
        return problems
    }

    private var signUpProblems: [AuthField: String] {
        var problems: [AuthField: String] = [:]
        problems[.signUpUsername] = AuthRules.username(signUpUsername)
        problems[.signUpDisplayName] = AuthRules.displayName(signUpDisplayName)
        problems[.signUpPassword] = AuthRules.password(signUpPassword)
        problems[.signUpConfirmation] = AuthRules.confirmation(signUpPassword, signUpConfirmation)
        return problems
    }

    private var canLogIn: Bool { logInProblems.isEmpty }
    private var canSignUp: Bool { signUpProblems.isEmpty }

    /// A rule only surfaces once the player has moved on from the field or
    /// tried to submit. Flagging a password as too short on its first keystroke
    /// would be noise, and the web form says nothing until submit either.
    ///
    /// A mismatched confirmation is the exception: it disables the submit
    /// button, so staying quiet until the field loses focus would leave the
    /// player looking at a dead button with no reason given.
    private func problem(for field: AuthField) -> String? {
        let problems = tab == .logIn ? logInProblems : signUpProblems
        guard let message = problems[field] else { return nil }
        if field == .signUpConfirmation, !signUpConfirmation.isEmpty { return message }
        return touched.contains(field) ? message : nil
    }

    // MARK: - Submission

    private func submitLogIn() {
        touched.formUnion([.logInUsername, .logInPassword])
        guard canLogIn else { return }
        focused = nil
        let username = AuthRules.normalized(username: loginUsername)
        let password = loginPassword
        Task { await store.logIn(username: username, password: password) }
    }

    private func submitSignUp() {
        touched.formUnion([.signUpUsername, .signUpDisplayName, .signUpPassword, .signUpConfirmation])
        guard canSignUp else { return }
        focused = nil
        let username = AuthRules.normalized(username: signUpUsername)
        let displayName = AuthRules.trimmed(signUpDisplayName)
        let password = signUpPassword
        let confirmation = signUpConfirmation
        Task {
            await store.signUp(username: username, displayName: displayName,
                               password: password, passwordConfirmation: confirmation)
        }
    }
}

// MARK: - Launch

/// `#startup.card.app-loading` — shown while `/api/session` is being read back.
struct LaunchView: View {
    var body: some View {
        NeoPanel(padding: 22) {
            VStack(spacing: 7) {
                LoadingMark()
                Eyebrow(text: "Restoring durable state")
                DisplayTitle(text: "Loading Wordflow", size: 26)
                Text("Checking for an active player session…")
                    .font(Typography.sans(15))
                    .foregroundStyle(Palette.muted)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 196)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Wordflow. Checking for an active player session.")
    }
}

// MARK: - Pieces

private enum AuthTab: String, CaseIterable, Identifiable {
    case logIn, signUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logIn: "Log in"
        case .signUp: "Sign up"
        }
    }
}

private enum AuthField: Hashable {
    case logInUsername, logInPassword
    case signUpUsername, signUpDisplayName, signUpPassword, signUpConfirmation
}

/// Both `.auth-card` forms stacked on a phone would bury the second one, so the
/// two headings become tabs drawn in the same bordered-pill idiom as `.quiet`.
private struct AuthTabPicker: View {
    @Binding var selection: AuthTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AuthTab.allCases) { tab in
                let chosen = tab == selection
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(Typography.sans(15, weight: .heavy))
                        .foregroundStyle(chosen ? .white : Palette.space)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(chosen ? Palette.uv : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(chosen ? Palette.space : Color.clear, lineWidth: Metrics.border))
                        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
            .fill(Palette.paper.opacity(0.94)))
        .inkBorder(Metrics.panelRadius)
        .hardShadow(offset: Metrics.buttonShadow, radius: Metrics.panelRadius)
        .animation(.easeOut(duration: 0.14), value: selection)
    }
}

/// `.auth-card label` + `.auth-card input`: an uppercase muted caption floating
/// above a 2px ink-bordered paper box.
private struct AuthTextField<Field: View>: View {
    var label: String
    var problem: String?
    @ViewBuilder var field: Field

    private var borderColor: Color { problem == nil ? Palette.space : Palette.coral }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(Typography.sans(12, weight: .heavy))
                .tracking(0.49)
                .foregroundStyle(Palette.muted)
                // `<label>Username<input></label>` is one accessible element.
                .accessibilityHidden(true)
            field
                .textFieldStyle(.plain)
                .font(Typography.sans(16))
                .foregroundStyle(Palette.space)
                .accessibilityLabel(label)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.paper))
                .inkBorder(10, color: borderColor)
            if let problem {
                // Its own element so VoiceOver reads the rule once, after the
                // field, rather than as part of the field's own announcement.
                Text(problem)
                    .font(Typography.sans(12, weight: .semibold))
                    .foregroundStyle(Palette.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Mirrors `normalizeUsername`, `validateDisplayName` and `passwordHash` in
/// `internal/api/auth.go` so a bad field is caught before the round trip.
private enum AuthRules {
    static func normalized(username raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func username(_ raw: String) -> String? {
        let value = normalized(username: raw)
        guard value.utf8.count >= 3, value.utf8.count <= 32 else {
            return "Username must be between 3 and 32 characters."
        }
        guard value.unicodeScalars.allSatisfy(isUsernameScalar) else {
            return "Username may contain letters, numbers, hyphens, and underscores."
        }
        return nil
    }

    static func displayName(_ raw: String) -> String? {
        let count = trimmed(raw).unicodeScalars.count
        guard count >= 2, count <= 24 else {
            return "Display name must be between 2 and 24 characters."
        }
        return nil
    }

    /// `validateSignupPasswords` in app.js sets exactly this custom validity.
    static func confirmation(_ password: String, _ confirmation: String) -> String? {
        guard password == confirmation else { return "Passwords do not match." }
        return nil
    }

    static func password(_ raw: String) -> String? {
        guard raw.utf8.count >= 8, raw.utf8.count <= 128 else {
            return "Password must be between 8 and 128 characters."
        }
        return nil
    }

    private static func isUsernameScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "0"..."9", "-", "_": true
        default: false
        }
    }
}
