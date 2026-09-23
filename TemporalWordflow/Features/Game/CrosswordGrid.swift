// Ports the #crossword grid and .cell rules from web/index.html and styles.css.
import SwiftUI

struct CrosswordGrid: View {
    var cells: [Cell]
    var rows: Int
    var columns: Int
    /// `aria-label` on the two grid containers in index.html.
    var label = "Crossword grid"
    /// `.cell { width: clamp(30px, 7.5vw, 46px) }`. The phone breakpoint drops
    /// that floor to `min(30px, (100vw - 140px) / columns)` so a wide board
    /// always fits; the floor here only stops a degenerate zero.
    var maxCellSize: CGFloat = 46
    var minCellSize: CGFloat = 10
    var spacing: CGFloat = 4

    var body: some View {
        CrosswordLayout(
            rows: rows, columns: columns, spacing: spacing,
            maxSide: maxCellSize, minSide: minCellSize
        ) {
            ForEach(cells) { cell in
                CrosswordCell(cell: cell)
                    .crosswordPosition(row: cell.row, column: cell.col)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Places the sparse cells on a square lattice and reports the exact size the
/// lattice needs, so the board never reserves space it does not use.
private struct CrosswordLayout: Layout {
    var rows: Int
    var columns: Int
    var spacing: CGFloat
    var maxSide: CGFloat
    var minSide: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let side = side(forWidth: proposal.width ?? .infinity)
        return CGSize(
            width: proposal.width ?? span(count: columns, side: side),
            height: span(count: rows, side: side))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let side = side(forWidth: bounds.width)
        // `.crossword { justify-content: center }`, never off the leading edge.
        let originX = max(bounds.minX,
                          bounds.minX + (bounds.width - span(count: columns, side: side)) / 2)
        for subview in subviews {
            let row = subview[CrosswordRow.self]
            let column = subview[CrosswordColumn.self]
            subview.place(
                at: CGPoint(
                    x: originX + CGFloat(column) * (side + spacing),
                    y: bounds.minY + CGFloat(row) * (side + spacing)),
                proposal: ProposedViewSize(width: side, height: side))
        }
    }

    private func side(forWidth width: CGFloat) -> CGFloat {
        guard columns > 0, width.isFinite else { return maxSide }
        let available = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return max(minSide, min(maxSide, available))
    }

    private func span(count: Int, side: CGFloat) -> CGFloat {
        CGFloat(count) * side + CGFloat(max(0, count - 1)) * spacing
    }
}

private struct CrosswordRow: LayoutValueKey {
    static let defaultValue = 0
}

private struct CrosswordColumn: LayoutValueKey {
    static let defaultValue = 0
}

private extension View {
    func crosswordPosition(row: Int, column: Int) -> some View {
        layoutValue(key: CrosswordRow.self, value: row)
            .layoutValue(key: CrosswordColumn.self, value: column)
    }
}

private struct CrosswordCell: View {
    var cell: Cell

    @State private var pop = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // 7pt on any ordinary board; only the 15-column puzzles shrink far
            // enough for a fixed radius to turn the tiles into circles.
            let radius = min(Metrics.tileRadius, side * 0.25)
            Text(cell.letter?.uppercased() ?? "")
                .font(.system(size: side * 0.52, weight: .black))
                .minimumScaleFactor(0.6)
                .foregroundStyle(state.foreground)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(state.background))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.space, lineWidth: min(Metrics.border, side * 0.09)))
        }
        .scaleEffect(pop ? 1.14 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.5), value: pop)
        .onChange(of: state) { _, _ in
            // A letter landing on the board should register physically.
            pop = true
            Task {
                try? await Task.sleep(nanoseconds: 180_000_000)
                pop = false
            }
        }
        .accessibilityLabel(state.label)
    }

    /// Mirrors the class ladder in `renderCrosswordInto`:
    /// `missed ? "missed" : hinted ? "hinted" : revealed ? "revealed" : ""`.
    private var state: CellState {
        if cell.isMissed { return .missed }
        if cell.hinted { return .hinted }
        if cell.revealed { return .revealed }
        return .hidden
    }
}

private enum CellState: Equatable {
    case hidden, revealed, hinted, missed

    var background: Color {
        switch self {
        case .hidden: Palette.paper
        case .revealed: Palette.uv
        case .hinted: Palette.lime
        case .missed: Palette.coral
        }
    }

    var foreground: Color {
        switch self {
        case .hidden: Palette.space
        case .revealed, .missed: .white
        case .hinted: Palette.space
        }
    }

    var label: String {
        switch self {
        case .hidden: "Hidden letter"
        case .revealed: "Found word letter"
        case .hinted: "Hint-revealed letter"
        case .missed: "Missed solution letter"
        }
    }
}

/// `.cell-legend` — the colour key printed under both grids.
struct CellLegend: View {
    var includeMissed = false

    var body: some View {
        FlowLayout(spacing: 16, alignment: .center) {
            item(Palette.uv, includeMissed ? "You found" : "Found word")
            item(Palette.lime, includeMissed ? "Hint revealed" : "Hint-revealed letter")
            if includeMissed { item(Palette.coral, "Missed") }
        }
        .font(Typography.sans(12))
        .foregroundStyle(Palette.muted)
        .frame(maxWidth: .infinity)
    }

    private func item(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 14, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Palette.space, lineWidth: Metrics.border))
            Text(label)
        }
        .accessibilityElement(children: .combine)
    }
}
