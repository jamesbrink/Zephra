import Observation

/// Where the phone is looking: which surface is up, whether the capsule is showing its
/// settings, and whether the prompt wants the keyboard.
///
/// The Mac's `WorkspaceSelection` in a phone's shape, and for the same reason it exists there:
/// which pane is up is a fact several places need to *write*, not only read. The library's
/// "Use as Reference" takes somebody to the canvas, and the canvas owns the capsule; neither
/// can reach a `@State` on the root, and threading a binding down through four surfaces to let
/// one menu item move a tab is worse than one object in the environment.
///
/// Focus is here for that same reason. The tap that opens the capsule happens on a view that
/// no longer exists by the time the editor is on screen, so the wish for the keyboard has to
/// outlive it: the collapsed line records that somebody asked for the keyboard, and the editor
/// mirrors the wish into its own `@FocusState` once it is mounted. A `@FocusState` on the
/// capsule could not be written from a view that is going away.
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
    /// Whether the prompt wants the keyboard. Never set by a frozen launch: a screenshot of
    /// the capsule is of the controls, and a keyboard over them hides most of what it is for.
    var promptIsFocused = false

    /// A selection that opens where this launch was told to.
    init(
        tab: MobileTab = MobilePreview.tab,
        capsuleIsExpanded: Bool = MobilePreview.capsuleIsExpanded
    ) {
        self.tab = tab
        self.capsuleIsExpanded = capsuleIsExpanded
    }

    /// Shows the settings, and asks for the keyboard when the prompt is what was tapped.
    ///
    /// One call rather than two writes, because the two facts have to move together: a tap on
    /// the prompt line means "let me type", and an editor that arrives without the keyboard
    /// costs a second tap for the same wish.
    func expandCapsule(focusingPrompt: Bool = false) {
        capsuleIsExpanded = true
        promptIsFocused = focusingPrompt
    }

    /// Puts the settings away, and the keyboard with them.
    ///
    /// The keyboard always goes: the editor is inside the settings, so leaving the wish up
    /// would bring the keyboard back the moment the capsule opened again.
    func collapseCapsule() {
        capsuleIsExpanded = false
        promptIsFocused = false
    }
}
