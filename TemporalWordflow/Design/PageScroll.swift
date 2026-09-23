import SwiftUI

/// The scrolling body every screen sits in.
///
/// `ImageRenderer` — which `Tools/preview.sh` uses to screenshot the app without
/// a simulator — renders a `ScrollView` as empty space. Routing every screen
/// through one container means the snapshot path can substitute a plain stack
/// and still exercise the real layout.
struct PageScroll<Content: View>: View {
    /// `.shell { width: min(1040px, …); margin: 0 auto }` — without this the
    /// page would stretch edge to edge on an iPad.
    var maxContentWidth: CGFloat = 1040
    var onRefresh: (() async -> Void)?
    @ViewBuilder var content: Content

    @Environment(\.isSnapshotRendering) private var isSnapshotRendering

    var body: some View {
        if isSnapshotRendering {
            VStack(spacing: 0) {
                column
                Spacer(minLength: 0)
            }
        } else {
            scroller
        }
    }

    private var column: some View {
        content
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var scroller: some View {
        if let onRefresh {
            ScrollView {
                column
            }
            .scrollIndicators(.hidden)
            .refreshable { await onRefresh() }
        } else {
            ScrollView {
                column
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct SnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the screen is being captured by `Tools/preview.sh`.
    var isSnapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}
