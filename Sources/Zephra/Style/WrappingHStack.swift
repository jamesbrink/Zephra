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
        let rows = Self.rows(of: sizes(of: subviews), within: width, spacing: horizontalSpacing)
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
        let sizes = sizes(of: subviews)
        var y = bounds.minY
        for row in Self.rows(of: sizes, within: bounds.width, spacing: horizontalSpacing) {
            var x = bounds.minX
            for index in row.indices {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(sizes[index])
                )
                x += sizes[index].width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    /// One line of the layout: which subviews are on it and how tall the tallest of them is.
    struct Row: Equatable {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func sizes(of subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    /// Fills lines left to right, breaking whenever the next subview would overhang `width`.
    /// A subview wider than the whole line gets a line to itself rather than an empty one
    /// before it.
    ///
    /// Over sizes rather than subviews, so the arithmetic can be pinned by a test without a
    /// view hierarchy to measure.
    nonisolated static func rows(of sizes: [CGSize], within width: CGFloat, spacing: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, size) in sizes.enumerated() {
            let advance = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, advance > width {
                rows.append(row)
                row = Row(indices: [index], width: size.width, height: size.height)
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
