/// One file in a model repository, as its listing describes it.
public struct RepositoryFile: Hashable, Sendable {
    /// The path inside the repository, which is also the path inside the download directory.
    public let path: String
    /// How many bytes the file is, which is what a transfer is checked against when it ends
    /// and what the progress fraction is weighted by.
    public let bytes: Int64
    /// The file's SHA-256 as lowercase hex, when the listing carries one. A mirror's index
    /// does; the hub's tree does not. A file that arrives at the right size but the wrong
    /// digest is thrown away and fetched again rather than kept.
    public let sha256: String?

    /// Creates a listed file.
    public init(path: String, bytes: Int64, sha256: String? = nil) {
        self.path = path
        self.bytes = bytes
        self.sha256 = sha256
    }
}
