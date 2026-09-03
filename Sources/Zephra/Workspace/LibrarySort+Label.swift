import ZephraEngine

/// What each order is called in the sort menu. In the app, like every other piece of copy.
extension LibrarySort {
    /// The menu item's words.
    var title: String {
        switch self {
        case .newestFirst: "Newest first"
        case .oldestFirst: "Oldest first"
        }
    }
}
