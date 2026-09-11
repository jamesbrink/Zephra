/// What happened to the library, in the three shapes an incremental list needs.
///
/// A reset rather than a diff when the query changes or the folder is rescanned wholesale: the
/// phone holds a page at a time, and reconciling a moved window against a diff is more rules
/// than re-sending the window it is looking at.
public enum LibraryChange: Codable, Hashable, Sendable {
    /// Start again from these entries; `total` is how many the library holds in all.
    case reset([LibraryEntry], total: Int)
    /// These entries are new or have changed.
    case upserted([LibraryEntry])
    /// These file names are gone.
    case removed([String])
}
