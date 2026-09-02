import Foundation
import ZephraCore

/// Checks that a local model directory holds what a loader will look for before the loader is
/// pointed at it, so a missing folder fails with a message instead of a crash.
///
/// What counts as complete differs by model family, so the entries are supplied rather than
/// hard-coded: a family declares its own once, at the point where it knows them.
public struct LocalSnapshot: Sendable {
    /// The entries a snapshot of this family must contain to be loadable.
    public let requiredEntries: [String]

    /// Creates a check for a family whose snapshots must contain `requiredEntries`.
    public init(requiredEntries: [String]) {
        self.requiredEntries = requiredEntries
    }

    /// Returns `directory` if it looks like a snapshot, or throws `BackendError.downloadFailed`
    /// naming the first missing entry.
    public func verified(_ directory: URL, descriptor: ModelDescriptor) throws -> URL {
        if let missing = missingEntry(in: directory) {
            throw BackendError.downloadFailed(
                "\(descriptor.fullName) is not at \(directory.path(percentEncoded: false)): missing \(missing)."
            )
        }
        return directory
    }

    /// The first thing a loadable snapshot needs that this directory does not have, or nil when
    /// it has them all. The non-throwing half of `verified`, for asking without committing.
    public func missingEntry(in directory: URL) -> String? {
        let files = FileManager.default
        return requiredEntries.first {
            !files.fileExists(atPath: directory.appending(path: $0).path(percentEncoded: false))
        }
    }
}
