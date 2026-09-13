import SwiftUI

/// Which picture the viewer was opened on, and which it is showing now.
///
/// The cover's item, and one value rather than the entry itself so that paging never
/// re-presents: its identity is the picture it opened on, which does not change, while
/// `shown` follows the pager. Both matter to the zoom transition. The system is told the
/// transition's source id when the cover goes up and never asks again, and Photos closes a
/// picture into the cell it is *now* over, not the one it opened on — so the cell under the
/// shown picture has to answer to the id the opened one was given, and no other cell may.
/// `sourceID(forCell:)` is that rule, and `ViewerOpeningTests` pins it.
struct ViewerOpening: Identifiable, Equatable {
    /// The picture the viewer opened on, whose name is the id the transition was given.
    let opened: CachedEntry
    /// The file name of the picture on screen now; the opened one until the pager moves.
    var shown: String

    /// The opened picture's name: what the cover is presented under, so paging changes the
    /// content and never the presentation.
    var id: String { opened.id }

    /// Opens on one picture.
    init(opened: CachedEntry) {
        self.opened = opened
        shown = opened.id
    }

    /// The transition source id a cell declares while the viewer is up, so the zoom back
    /// lands on the cell of the picture on screen: the cell under the shown picture answers
    /// to the opened one's name, and every other cell declares no source at all.
    ///
    /// None rather than its own name, because the system follows a source that is added or
    /// taken away and not one whose id changes: with every cell keeping a source and the two
    /// names swapped between the shown cell and the opened one, the zoom back went to the
    /// cell it opened from whatever the pager had done.
    func sourceID(forCell fileName: String) -> String? {
        fileName == shown ? opened.id : nil
    }
}

extension EnvironmentValues {
    /// The viewer's opening while it is up, for the cells that are its transition's sources;
    /// nil while it is down.
    @Entry var viewerOpening: ViewerOpening?
    /// The namespace the viewer's zoom transition runs in, from the surface that presents it;
    /// nil for a cell drawn where no viewer opens.
    @Entry var viewerNamespace: Namespace.ID?
    /// How the viewer says which picture it has paged to.
    @Entry var viewerPaged: (String) -> Void = { _ in }
}
