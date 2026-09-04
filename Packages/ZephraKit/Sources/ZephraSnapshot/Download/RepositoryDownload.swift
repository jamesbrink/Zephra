import Foundation

/// One repository, which of its files to take, and where they go.
///
/// A model is not always one repository: Qwen-Image's four-step distillation is published apart
/// from the weights it distils, and both have to be here before anything can be built. So a
/// download is a list of these rather than a single repository, listed and tallied together, and
/// the bar runs once from nothing to everything instead of twice from nothing to a hundred.
public struct RepositoryDownload: Hashable, Sendable {
    /// The Hugging Face repository to read.
    public let repoID: String
    /// The revision to read it at.
    public let revision: String
    /// The globs worth taking from it; empty takes the repository whole.
    public let patterns: [String]
    /// The directory its files land in, flat, named as the repository names them.
    public let destination: URL

    /// Names one repository's share of a download.
    public init(repoID: String, revision: String = "main", patterns: [String], destination: URL) {
        self.repoID = repoID
        self.revision = revision
        self.patterns = patterns
        self.destination = destination
    }
}
