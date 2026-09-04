import Foundation
import ZephraCore

/// Why a download stopped, in the terms the retry and the message both need.
///
/// Two questions are asked of every failure: is another try worth making, and what does the
/// person reading it do next. Both are answered here rather than at each call site, because
/// every family downloads the same way and so fails the same way.
public enum ModelDownloadError: Error, Hashable, Sendable {
    /// The hub has no such repository, or none at that revision.
    case repositoryNotFound(repoID: String)
    /// The listing arrived but was not the array of entries the endpoint documents.
    case unreadableListing
    /// The repository is there, and nothing in it matches the files the descriptor asks for.
    /// A catalog written against a repository that has since been rearranged, in practice.
    case nothingMatched(repoID: String)
    /// The repository is there but the file the listing named is not, which means the listing
    /// and the download disagree — a revision that moved under the transfer, in practice.
    case fileNotFound(path: String)
    /// The hub answered with a status that will not change: a login wall, a rate of requests
    /// it will not serve, a request it will not accept.
    case refused(status: Int, path: String)
    /// The transfer broke: the connection went, the server had a moment, the file ended early.
    /// The bytes already written stay on disk, so trying again continues from them.
    case interrupted(reason: String)
    /// The listing named a path that would land outside the download's own folder.
    case unsafePath(path: String)

    /// Whether another try could end differently. A missing repository or file and a refusal
    /// are answers; anything else is an accident worth a pause and another go.
    public var isPermanent: Bool {
        switch self {
        case .repositoryNotFound, .fileNotFound, .unreadableListing, .nothingMatched, .unsafePath: true
        case .refused(let status, _): DownloadRetry.isPermanentStatus(status)
        case .interrupted: false
        }
    }

    /// What to tell someone, without the jargon of the layer it came from.
    public var reason: String {
        switch self {
        case .repositoryNotFound(let repoID):
            "Hugging Face has no repository called \(repoID), or not at that revision."
        case .unreadableListing:
            "Hugging Face answered with something this version of Zephra cannot read."
        case .nothingMatched(let repoID):
            "Nothing in \(repoID) matches the files this version of Zephra asks for."
        case .fileNotFound(let path):
            "\(path) is listed in the repository but could not be fetched."
        case .refused(let status, let path):
            "Hugging Face refused to serve \(path) (HTTP \(status))."
        case .interrupted(let reason):
            reason
        case .unsafePath(let path):
            "The repository names a file outside its own folder (\(path)), which Zephra will not write."
        }
    }
}
