/// The order the library's images are listed in.
public enum LibrarySort: String, Hashable, Sendable, CaseIterable {
    /// Most recently made first, the default: what you just did is at the top.
    case newestFirst = "newest-first"
    /// Oldest first, for walking a long session from where it started.
    case oldestFirst = "oldest-first"
}
