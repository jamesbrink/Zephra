import Foundation

/// What the arrow keys and the mouse do to a selection, worked out without a view.
///
/// Pure functions in, one outcome out: the grid says what it is showing and what is selected,
/// and this says what should be selected next and what to scroll into view. Keeping it out of
/// the view is what makes "down from the last row of one day lands in the next day at the same
/// column" a thing that can be tested rather than a thing that is fiddled with.
public enum LibraryCursor {
    /// Which way the selection is being moved.
    public enum Direction: Hashable, Sendable {
        /// The previous image in reading order, across day boundaries.
        case left
        /// The next image in reading order, across day boundaries.
        case right
        /// One row up, or into the day above at the same column.
        case up
        /// One row down, or into the day below at the same column.
        case down
        /// The first image of all.
        case home
        /// The last image of all.
        case end
    }

    /// Which keys were held during a click.
    public struct ClickModifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// Add or remove this one image, leaving the rest of the selection alone.
        public static let command = ClickModifiers(rawValue: 1 << 0)
        /// Select everything between the anchor and this image.
        public static let shift = ClickModifiers(rawValue: 1 << 1)
    }

    /// What the selection should become.
    public struct Outcome: Hashable, Sendable {
        /// The images that end up selected.
        public let ids: Set<LibraryItem.ID>
        /// The fixed end a shift-selection extends from next time.
        public let anchor: LibraryItem.ID?
        /// The image to scroll into view, when the selection moved somewhere that may be off
        /// screen. Nil after a click, which is on something already visible.
        public let reveal: LibraryItem.ID?

        /// Describes one change of selection.
        public init(ids: Set<LibraryItem.ID>, anchor: LibraryItem.ID?, reveal: LibraryItem.ID? = nil) {
            self.ids = ids
            self.anchor = anchor
            self.reveal = reveal
        }
    }

    /// What a click does, given what was held down.
    ///
    /// Shift keeps the anchor where it was, because a run of shift-clicks should grow and shrink
    /// one selection rather than start a new one each time. Everything else moves the anchor to
    /// what was clicked.
    public static func click(
        _ id: LibraryItem.ID,
        in sections: [LibrarySection],
        modifiers: ClickModifiers,
        selection: Set<LibraryItem.ID>,
        anchor: LibraryItem.ID?
    ) -> Outcome {
        let flat = order(of: sections)
        guard modifiers.contains(.shift), let anchor, flat.contains(anchor) else {
            if modifiers.contains(.command) {
                var ids = selection
                if !ids.insert(id).inserted { ids.remove(id) }
                return Outcome(ids: ids, anchor: id)
            }
            return Outcome(ids: [id], anchor: id)
        }
        let extent = range(from: anchor, to: id, in: flat)
        let ids = modifiers.contains(.command) ? selection.union(extent) : extent
        return Outcome(ids: ids, anchor: anchor)
    }

    /// Selects everything the grid is showing.
    public static func selectAll(in sections: [LibrarySection]) -> Outcome {
        let flat = order(of: sections)
        return Outcome(ids: Set(flat), anchor: flat.first)
    }

    /// Every image the grid is showing, in reading order across the day headings.
    static func order(of sections: [LibrarySection]) -> [LibraryItem.ID] {
        sections.flatMap { $0.items.map(\.id) }
    }

    /// The images between two, inclusive, whichever way round they are.
    static func range(
        from anchor: LibraryItem.ID,
        to id: LibraryItem.ID,
        in flat: [LibraryItem.ID]
    ) -> Set<LibraryItem.ID> {
        guard let first = flat.firstIndex(of: anchor), let second = flat.firstIndex(of: id) else {
            return [id]
        }
        return Set(flat[min(first, second)...max(first, second)])
    }
}
