import SwiftUI

/// A vertical stack whose rows are all laid out at one width: the width proposed, or the
/// widest row's own minimum when a row cannot go that narrow.
///
/// A `VStack` proposes one width to every row and takes the widest as its own, but lays the
/// others out at what it proposed, so a row that refuses to shrink stands out past the rest.
/// In the prompt capsule that is the settings row once a strength slider joins it, and the
/// result was a prompt and a divider that stopped short of the Generate button under them.
/// Asking each row for its size at a width of zero is asking for its minimum, which is a
/// question about the row and not about the layout it last had, so the answer cannot feed back
/// into itself the way a measured width would.
struct SharedWidthRows: Layout {
    /// The gap between rows.
    var spacing: CGFloat = 12

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let width = rowWidth(proposal: proposal, subviews: subviews)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let gaps = CGFloat(max(0, subviews.count - 1)) * spacing
        return CGSize(width: width, height: heights.reduce(0, +) + gaps)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let width = bounds.width
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            subview.place(
                at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: height))
            y += height + spacing
        }
    }

    /// The proposed width, or the widest minimum among the rows when one needs more.
    private func rowWidth(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        let minimum = subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width }
            .max() ?? 0
        return max(proposal.width ?? minimum, minimum)
    }
}
