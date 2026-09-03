import Foundation

/// One thing narrowing the library, shown as a removable token over the grid.
///
/// A token is a view of `LibraryQuery`, not state of its own: the query says what its tokens
/// are, and removing one hands back the query without that part.
public enum LibraryQueryToken: Hashable, Sendable {
    /// The scope, when it is anything but `.all`.
    case scope(LibraryScope)
    /// The model filter, by descriptor identifier.
    case model(String)
    /// The tag filter.
    case tag(String)
    /// The search text.
    case search(String)
}
