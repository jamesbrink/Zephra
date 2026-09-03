/// Which of the window's two panes is showing.
///
/// The sidebar and the toolbar are the same in both; only the wide half of the window changes.
/// Two is the whole set on purpose: a pane per feature would put the shortcut for the one you
/// want out of reach.
enum WorkspacePane: String, CaseIterable, Identifiable {
    /// The picture being worked on, with the prompt capsule over it.
    case canvas
    /// Everything made so far, as a grid.
    case library

    var id: String { rawValue }

    /// What the toolbar's toggle calls it.
    var title: String {
        switch self {
        case .canvas: "Canvas"
        case .library: "Library"
        }
    }

    /// The symbol beside that word.
    var systemImage: String {
        switch self {
        case .canvas: "photo"
        case .library: "square.grid.2x2"
        }
    }
}
