/// One file in a model repository, as its listing describes it.
public struct RepositoryFile: Hashable, Sendable {
    /// The path inside the repository, which is also the path inside the download directory.
    public let path: String
    /// How many bytes the file is, which is what a transfer is checked against when it ends
    /// and what the progress fraction is weighted by.
    public let bytes: Int64

    /// Creates a listed file.
    public init(path: String, bytes: Int64) {
        self.path = path
        self.bytes = bytes
    }
}
