import SwiftUI

/// Tokens laid left to right, wrapping onto as many lines as they need.
///
/// A `Layout` rather than a stack of rows worked out in advance: the widths depend on the
/// words, the words depend on the library, and a phone is narrow enough that four tags is
/// often two lines. Thirty lines of arithmetic is the price of never having to guess.
struct TagFlow: Layout {
    /// The gap between two tokens, across and down.
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(of: subviews, in: width)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height + spacing }
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width,
                      height: max(0, height - spacing))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        var y = bounds.minY
        for row in rows(of: subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    /// One line of tokens: which of them, how wide and how tall.
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// The tokens broken into lines that fit `width`.
    private func rows(of subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if next > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
