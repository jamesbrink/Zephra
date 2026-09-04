import Foundation

/// Where the library viewer's arrow keys and its bar's own buttons take it: the next or
/// previous image in the grid's own order, and where the one on screen sits among the rest.
///
/// A namespace of pure functions over `[LibrarySection]`, the same shape as `LibraryCursor` and
/// built on the same flattened order it uses, so stepping through the viewer is something a
/// test can check without a window either.
public enum LibraryViewerStep {
    /// Which way a step moves.
    public enum Direction: Sendable {
        /// The image before this one in the grid's order.
        case previous
        /// The image after this one in the grid's order.
        case next
    }

    /// Where a shown image sits: its 1-based place, and how many there are to step through, so
    /// the bar can say "3 of 40" directly.
    public struct Position: Hashable, Sendable {
        public let index: Int
        public let count: Int

        public init(index: Int, count: Int) {
            self.index = index
            self.count = count
        }
    }

    /// The image a step in `direction` lands on, or nil at either end, or when `id` is not
    /// something the grid is currently showing — a filter narrowed under the viewer, most likely.
    public static func neighbour(
        of id: LibraryItem.ID, direction: Direction, in sections: [LibrarySection]
    ) -> LibraryItem.ID? {
        let flat = LibraryCursor.order(of: sections)
        guard let index = flat.firstIndex(of: id) else { return nil }
        switch direction {
        case .previous: return flat.indices.contains(index - 1) ? flat[index - 1] : nil
        case .next: return flat.indices.contains(index + 1) ? flat[index + 1] : nil
        }
    }

    /// Where `id` sits among everything the grid is showing, or nil when it is not shown at
    /// all — the same case `neighbour(of:direction:in:)` answers nil for.
    public static func position(of id: LibraryItem.ID, in sections: [LibrarySection]) -> Position? {
        let flat = LibraryCursor.order(of: sections)
        guard let index = flat.firstIndex(of: id) else { return nil }
        return Position(index: index + 1, count: flat.count)
    }
}
