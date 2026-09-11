import Observation

/// Where the phone is looking: which surface is up, and whether the capsule is showing its
/// settings.
///
/// The Mac's `WorkspaceSelection` in a phone's shape, and for the same reason it exists there:
/// which pane is up is a fact several places need to *write*, not only read. The library's
/// "Use as Reference" takes somebody to the canvas, and the canvas owns the capsule; neither
/// can reach a `@State` on the root, and threading a binding down through four surfaces to let
/// one menu item move a tab is worse than one object in the environment.
///
/// A fact about this phone rather than one that came over the link, which is why it is an
/// object of its own beside `LinkClient` rather than a field on it. Nothing here is persisted:
/// a launch opens on the canvas, or on whatever a frozen preview state asked for.
@Observable
final class MobileSelection {
    /// The surface showing. Its starting value comes from the frozen preview state, so a
    /// screenshot build opens on the surface it was asked for.
    var tab: MobileTab
    /// Whether the capsule is showing its settings. A frozen launch can open with it up, which
    /// is the only way to photograph the controls.
    var capsuleIsExpanded: Bool

    /// A selection that opens where this launch was told to.
    init(tab: MobileTab = MobilePreview.tab, capsuleIsExpanded: Bool = MobilePreview.capsuleIsExpanded) {
        self.tab = tab
        self.capsuleIsExpanded = capsuleIsExpanded
    }
}
