import SwiftUI

/// A row that runs onto the next line when it runs out of width.
///
/// SwiftUI has no such stack, and the alternatives are worse: a `LazyVGrid` gives every column
/// the same width, which looks wrong for chips of different lengths, and measuring text by hand
/// to lay it out in a `VStack` is the same arithmetic with none of the layout system's help.
struct WrappingHStack: Layout {
    /// The gap between two chips on the same line.
    var horizontalSpacing: CGFloat = 6
    /// The gap between two lines.
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = rows(of: subviews, within: width)
        let height = rows.map(\.height).reduce(0, +)
            + verticalSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(of: subviews, within: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    /// One line of the layout: which subviews are on it and how tall the tallest of them is.
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Fills lines left to right, breaking whenever the next subview would overhang `width`.
    /// A subview wider than the whole line gets a line to itself rather than an empty one
    /// before it.
    private func rows(of subviews: Subviews, within width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let advance = row.indices.isEmpty ? size.width : row.width + horizontalSpacing + size.width
            if !row.indices.isEmpty, advance > width {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = advance
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

#Preview("Wrapping") {
    WrappingHStack {
        ForEach(["street at night", "typography tests", "portraits", "long exposure", "fog"], id: \.self) {
            Chip($0)
        }
    }
    .padding(24)
    .frame(width: 240)
}
