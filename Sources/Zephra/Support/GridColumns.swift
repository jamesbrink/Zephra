import CoreGraphics

/// How many cells an adaptive grid fits across a width, which is what up and down move by.
///
/// The same arithmetic `LazyVGrid` does for `GridItem(.adaptive(minimum: edge))`: the usable
/// width is what is left inside the horizontal inset, and each column costs an edge plus one
/// gap, with the last gap given back. Shared by the library grid and the reference picker so
/// neither can disagree with its own layout about what a row holds. Never fewer than one:
/// a pane narrower than a cell still lays one cell per row.
nonisolated enum GridColumns {
    static func count(width: CGFloat, edge: CGFloat, spacing: CGFloat, inset: CGFloat) -> Int {
        let usable = width - 2 * inset + spacing
        return max(1, Int(usable / (edge + spacing)))
    }
}
