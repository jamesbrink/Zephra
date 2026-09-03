import Observation

/// What is selected in the library grid, and the two things the keyboard needs to move it.
///
/// Separate from `LibraryIndex` on purpose: a selection is about a view, not about the folder.
/// The grid can be rebuilt by a rescan under a selection that survives it, and a second window
/// would have its own.
@MainActor
@Observable
public final class LibrarySelection {
    /// The selected images, by path.
    public var ids: Set<LibraryItem.ID> = []
    /// The fixed end a shift-selection extends from.
    public var anchor: LibraryItem.ID?
    /// How many cells the grid is currently laying out per row, which is what up and down move
    /// by. The grid measures itself and writes it here.
    public var columns: Int = 1

    /// An empty selection.
    public init() {}

    /// How many images are selected.
    public var count: Int { ids.count }

    /// Whether one image is selected.
    public func contains(_ id: LibraryItem.ID) -> Bool { ids.contains(id) }

    /// The one selected image, or nil when none or several are: the inspector's whole question.
    public var single: LibraryItem.ID? { ids.count == 1 ? ids.first : nil }

    /// Selects nothing.
    public func clear() {
        ids = []
        anchor = nil
    }

    /// Adopts what a cursor move or click worked out.
    public func apply(_ outcome: LibraryCursor.Outcome) {
        ids = outcome.ids
        anchor = outcome.anchor
    }

    /// Drops anything that is no longer on screen, after a rescan or a change of query.
    public func keeping(_ available: Set<LibraryItem.ID>) {
        ids.formIntersection(available)
        if let anchor, !available.contains(anchor) { self.anchor = ids.first }
    }
}
