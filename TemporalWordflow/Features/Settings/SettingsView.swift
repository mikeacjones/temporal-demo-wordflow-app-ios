// No web counterpart: the browser build is served from its own API origin, so
// only iOS needs an editable server address. The rest restates the `header`
// lockup and the Player Workflow / Log out links of web/index.html.
//
// Built from the app's own panels rather than a stock `Form`, so the screen
// reads as part of Wordflow instead of as a system settings sheet.

import SwiftUI

struct SettingsView: View {
    var onDismiss: () -> Void

    @Environment(AppStore.self) private var store
    @State private var serverText = ""
    @State private var invalidAddress = false

    var body: some View {
        NavigationStack {
            PageScroll {
                VStack(alignment: .leading, spacing: 20) {
                    serverSection
                    if store.player != nil { sessionSection }
                    aboutSection
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .interactiveDismissKeyboard()
            .background(WordflowBackground())
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done", action: onDismiss)
                        .font(Typography.sans(16, weight: .heavy))
                }
            }
        }
        .tint(Palette.uv)
        .task { serverText = store.baseURLString }
    }

    // MARK: - Server

    private var serverSection: some View {
        NeoPanel(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Wordflow server")
                TextField(ServerSettings.defaultBaseURLString, text: $serverText)
                    .serverAddressField()
                    .font(Typography.mono(14, weight: .medium))
                    .foregroundStyle(Palette.space)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.paper))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(invalidAddress ? Palette.coral : Palette.space,
                                      lineWidth: Metrics.border))
                    .accessibilityLabel("Wordflow server address")
                    .onChange(of: serverText) { _, _ in invalidAddress = false }
                    .onSubmit(save)

                // `Text(verbatim:)` so the example URL is not auto-linked.
                Text(verbatim: invalidAddress
                     ? "That server address is not valid."
                     : "The API the app talks to. The README runs it on http://localhost:8080.")
                    .font(Typography.sans(12))
                    .foregroundStyle(invalidAddress ? Palette.coral : Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Use default") { serverText = ServerSettings.defaultBaseURLString }
                        .buttonStyle(QuietButtonStyle(compact: true))
                    Spacer(minLength: 8)
                    Button("Save", action: save)
                        .buttonStyle(QuietButtonStyle(fill: Palette.lavender, compact: true))
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Session

    private var sessionSection: some View {
        NeoPanel(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Session")
                if let displayName = store.player?.displayName {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as")
                            .font(Typography.sans(12, weight: .heavy))
                            .foregroundStyle(Palette.muted)
                        Text(displayName)
                            .font(Typography.mono(14, weight: .heavy))
                            .foregroundStyle(Palette.space)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                HStack(spacing: 10) {
                    PendingButton(
                        title: "Player Workflow ↗",
                        busyTitle: "Opening…",
                        style: QuietButtonStyle(compact: true),
                        isBusy: store.isBusy(.workflowLink)
                    ) {
                        Task {
                            await store.openPlayerWorkflow()
                            onDismiss()
                        }
                    }
                    .fixedSize()
                    Spacer(minLength: 8)
                    PendingButton(
                        title: "Log out",
                        busyTitle: "Logging out…",
                        style: QuietButtonStyle(foreground: Palette.coral, compact: true),
                        isBusy: store.isBusy(.logOut)
                    ) {
                        Task {
                            await store.logOut()
                            onDismiss()
                        }
                    }
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        NeoPanel(padding: 18, fill: AnyShapeStyle(LinearGradient(
            colors: [Palette.paper, Palette.lavender],
            startPoint: .topLeading, endPoint: .bottomTrailing))) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    BrandMark(size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "A durable word game")
                        Text("Temporal Wordflow")
                            .font(Typography.display(20))
                            .tracking(-0.7)
                            .foregroundStyle(Palette.space)
                        Text("Build words. Preserve state. Survive failure.")
                            .font(Typography.sans(13))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Every player, campaign and level is a Temporal Workflow on the server. "
                     + "The app keeps no local database — it reads that durable state back over "
                     + "the API on each move.")
                    .font(Typography.sans(13))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private var canSave: Bool {
        !serverText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        // The store's notice banner belongs to RootView, which this sheet covers,
        // so a rejected address has to report itself in the form.
        if store.updateBaseURL(serverText) {
            onDismiss()
        } else {
            invalidAddress = true
        }
    }
}

private extension View {
    @ViewBuilder
    func serverAddressField() -> some View {
        #if os(iOS)
        self.keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.done)
        #else
        self.autocorrectionDisabled(true)
        #endif
    }
}
