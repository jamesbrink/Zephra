/// Which of the app's three surfaces a panel is.
///
/// There are only three, and adding a fourth should take an argument: every surface in the
/// window is one of these, which is what keeps the interface looking like one thing.
enum ChromePanelStyle {
    /// Over the picture: system material, the capsule radius, a hairline, and a shadow.
    case floating
    /// Inside another surface: a quiet fill, the card radius, and nothing else.
    case inset
    /// Something the model is working on right now, in safelight amber.
    case warning
}
