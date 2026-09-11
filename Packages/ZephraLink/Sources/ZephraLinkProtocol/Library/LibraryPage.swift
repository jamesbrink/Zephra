/// One window onto the library, which is how the phone reads a folder of thousands.
public struct LibraryPage: Codable, Hashable, Sendable {
    /// The entries in this window, newest first.
    public var entries: [LibraryEntry]
    /// Where the window starts, counting from zero.
    public var offset: Int
    /// How many entries the library holds in all, so the list can size its scroller.
    public var total: Int

    /// Creates a page.
    public init(entries: [LibraryEntry], offset: Int, total: Int) {
        self.entries = entries
        self.offset = offset
        self.total = total
    }
}
