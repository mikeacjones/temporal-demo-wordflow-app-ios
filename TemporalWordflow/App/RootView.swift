// The shell around every screen: the page background, the brand lockup and
// status rail from web/index.html's <header>, and the #notice toast.
import SwiftUI

struct RootView: View {
    /// The preview renderer in Tools/ drives the store itself, so it renders the
    /// shell without letting it restore a session underneath.
    var restoresSession = true

    @Environment(AppStore.self) private var store

    @State private var showingLeaderboard = false
    @State private var showingSettings = false

    var body: some View {
        @Bindable var store = store
        return ZStack(alignment: .top) {
            WordflowBackground()

            VStack(spacing: 0) {
                header
                screen
            }

            if let notice = store.notice {
                NoticeBanner(message: notice.message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { store.dismissNotice() }
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: store.notice)
        .animation(.easeInOut(duration: 0.2), value: store.phase)
        .sheet(isPresented: $showingLeaderboard) {
            LeaderboardView { showingLeaderboard = false }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView { showingSettings = false }
        }
        .sheet(item: $store.presentedWorkflow) { link in
            WorkflowExplorerView(link: link) { store.dismissWorkflow() }
        }
        .task {
            guard restoresSession else { return }
            Haptics.prepare()
            await store.launch()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        switch store.phase {
        case .launching, .authentication:
            fullLockup
        case .catalog, .game, .complete:
            compactBar
        }
    }

    /// The `.brand-lockup` header plus `.status-rail`, shown while signed out.
    private var fullLockup: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                BrandMark(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "A durable word game")
                    Text("Temporal Wordflow")
                        // `h1 { font-size: clamp(2rem, 7vw, 4rem); letter-spacing: -.055em }`
                        // — 7vw on a 393pt phone resolves to 27.5pt.
                        .font(Typography.display(28))
                        .tracking(-28 * 0.055)
                        .foregroundStyle(Palette.space)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("Build words. Preserve state. Survive failure.")
                        .font(Typography.sans(13))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 5)
                }
                Spacer(minLength: 0)
            }
            StatusRail()
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    /// A slim signed-in bar: the header links from index.html, condensed.
    private var compactBar: some View {
        HStack(spacing: 10) {
            BrandMark(size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("Temporal Wordflow")
                    .font(Typography.sans(15, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.space)
                if let name = store.player?.displayName {
                    Text(name)
                        .font(Typography.mono(10, weight: .heavy))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Button { showingLeaderboard = true } label: {
                Image(systemName: "trophy")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Leaderboard")

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    // MARK: - Screens

    @ViewBuilder
    private var screen: some View {
        switch store.phase {
        case .launching:
            LaunchView()
        case .authentication:
            AuthView(showingSettings: $showingSettings)
        case .catalog:
            CatalogView()
        case .game:
            GameView()
        case .complete:
            CompleteView()
        }
    }
}

/// The circular icon affordance in the signed-in bar, in the app's own style.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Palette.space)
            .frame(width: 38, height: 38)
            .background(Circle().fill(configuration.isPressed ? Palette.lavender : Palette.paper))
            .overlay(Circle().strokeBorder(Palette.space, lineWidth: Metrics.border))
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}
