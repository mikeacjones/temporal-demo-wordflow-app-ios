import SwiftUI

/// Wrapping row layout, used wherever the stylesheet relies on
/// `display: flex; flex-wrap: wrap` — level chips, rejected words, answer pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat? = nil
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } +
            CGFloat(max(0, rows.count - 1)) * (lineSpacing ?? spacing)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews: subviews, width: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat
            switch alignment {
            case .center: x = bounds.minX + (bounds.width - row.width) / 2
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX
            }
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + (lineSpacing ?? spacing)
        }
    }

    private struct Item { var index: Int; var size: CGSize }
    private struct Row { var items: [Item] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty && needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(Item(index: index, size: size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
