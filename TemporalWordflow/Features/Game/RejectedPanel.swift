// Ports the .rejected-panel aside ("Not in the wordflow") from web/index.html.
import SwiftUI

struct RejectedPanel: View {
    var words: [String]

    /// `.rejected-words { max-height: 180px; overflow-y: auto }` — the web panel
    /// clips and scrolls. A nested scroll inside the page would fight the page
    /// gesture, so the list collapses to its newest entries instead.
    @State private var isExpanded = false

    private static let collapsedLimit = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Not in the wordflow")
                    .font(Typography.display(17))
                    .tracking(-0.35)
                    .foregroundStyle(Palette.space)
                Spacer(minLength: 8)
                if !words.isEmpty {
                    Text("\(words.count)")
                        .font(Typography.mono(12, weight: .heavy))
                        .foregroundStyle(Palette.muted)
                }
            }

            if words.isEmpty {
                Text("No missed words yet.")
                    .font(Typography.sans(13))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Newest first, exactly as the durable game history returns them.
                let hidden = isExpanded ? 0 : max(0, words.count - Self.collapsedLimit)
                WrappingWords(words: isExpanded ? words : Array(words.prefix(Self.collapsedLimit)))
                if hidden > 0 || isExpanded {
                    Button(isExpanded ? "Show fewer" : "+\(hidden) more") {
                        withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
                    }
                    .buttonStyle(QuietButtonStyle(compact: true))
                    .fixedSize()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [Palette.paper, Palette.lavender],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .inkBorder(14)
        .hardShadow(offset: CGSize(width: 4, height: 5), color: Palette.space.opacity(0.11), radius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Not in the wordflow")
    }
}

/// `.rejected-words li` chips, flowing onto as many lines as they need.
private struct WrappingWords: View {
    var words: [String]

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word.uppercased())
                    .font(Typography.sans(13, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(Palette.space)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                        .fill(Palette.paper))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1))
            }
        }
    }
}
