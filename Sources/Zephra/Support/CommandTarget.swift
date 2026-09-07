import ZephraCore
import ZephraEngine

/// What the file commands in the menu bar are about right now: the picture on the canvas, the
/// images chosen in the library grid, or nothing.
///
/// Decided from what is on screen and nothing else. The canvas's picture counts only while the
/// canvas pane is up and is showing it — while it follows a run there is no file yet, only
/// frames — and the library's selection counts only while the grid has the keyboard. There is
/// deliberately no fallback from one to the other: ⌘⌫ pressed over an empty library selection
/// must grey out rather than reach past the grid and delete whatever the canvas last showed.
enum CommandTarget: Equatable {
    /// Nothing to act on, which is what greys every file command out.
    case none
    /// The image on the canvas, which may not have reached the disk yet.
    case canvas(GeneratedImage)
    /// Images chosen in the library grid, which are files.
    case library([LibraryItem])

    /// Works out the target from the window's state.
    ///
    /// `gridSelection` is the grid's focus-scoped selection — nil while the grid does not have
    /// the keyboard — so ⌘A and ⌘⌫ in the sidebar's search field still mean the text there.
    /// `sections` is what the grid is showing; an id the query has since filtered out is not on
    /// screen and so is not a target.
    static func resolve(
        pane: WorkspacePane,
        isShowingRun: Bool,
        current: GeneratedImage?,
        gridSelection: Set<LibraryItem.ID>?,
        sections: [LibrarySection]
    ) -> CommandTarget {
        switch pane {
        case .canvas:
            guard !isShowingRun, let current else { return .none }
            return .canvas(current)
        case .library:
            guard let gridSelection, !gridSelection.isEmpty else { return .none }
            let chosen = sections.flatMap(\.items).filter { gridSelection.contains($0.id) }
            return chosen.isEmpty ? .none : .library(chosen)
        }
    }

    /// Whether there is nothing to act on.
    var isEmpty: Bool { self == .none }

    /// How many images the commands would act on.
    var count: Int {
        switch self {
        case .none: 0
        case .canvas: 1
        case .library(let items): items.count
        }
    }

    /// The one library item chosen, or nil for the canvas, for none, or for several.
    var singleItem: LibraryItem? {
        guard case .library(let items) = self, items.count == 1 else { return nil }
        return items.first
    }

    /// Whether there is exactly one picture or clip to act on, and whether it is a clip — the
    /// canvas's picture (`GeneratedImage.isVideo` reads its own settings, so a clip's poster
    /// answers true before it is indexed too) or the one item chosen in the grid. Nil for none
    /// and for several, the same as `singleItem`; the wrapped value is whether it is a clip.
    var singlePicture: Bool? {
        switch self {
        case .none: return nil
        case .canvas(let image): return image.isVideo
        case .library: return singleItem?.isVideo
        }
    }

    /// "Export" rather than "Save as": nothing is a document with changes to keep, and the
    /// picture is already on the disk. Title Case, because these are menu items.
    var exportTitle: String { count > 1 ? "Export \(count) Images…" : "Export…" }

    var copyTitle: String { count > 1 ? "Copy \(count) Images" : "Copy Image" }

    var shareTitle: String { count > 1 ? "Share \(count) Images…" : "Share…" }

    var deleteTitle: String { count > 1 ? "Delete \(count) Images" : "Delete Image" }

    /// "Animate from Last Frame" over a clip, since its poster is only the frame it starts on;
    /// "Animate" otherwise, for one picture or for no target at all, which is what greys the
    /// item out regardless of what its title says.
    var animateTitle: String { singlePicture == true ? "Animate from Last Frame" : "Animate" }
}
