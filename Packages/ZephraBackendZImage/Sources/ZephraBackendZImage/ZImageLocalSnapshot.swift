import Foundation
import ZephraCore

/// Checks that a local model directory holds what the pipeline will look for before the
/// loader is pointed at it, so a missing folder fails with a message instead of a crash.
nonisolated enum ZImageLocalSnapshot {
    /// The files every Z-Image snapshot must contain to be loadable.
    private static let requiredEntries = ["model_index.json", "transformer", "text_encoder", "vae"]

    /// Returns `directory` if it looks like a snapshot, or throws `BackendError.downloadFailed`
    /// naming the first missing entry.
    static func verified(_ directory: URL, descriptor: ModelDescriptor) throws -> URL {
        if let missing = missingEntry(in: directory) {
            throw BackendError.downloadFailed(
                "\(descriptor.fullName) is not at \(directory.path(percentEncoded: false)): missing \(missing)."
            )
        }
        return directory
    }

    /// The first thing a loadable snapshot needs that this directory does not have, or nil when
    /// it has them all. The non-throwing half of `verified`, for asking without committing.
    static func missingEntry(in directory: URL) -> String? {
        let files = FileManager.default
        return requiredEntries.first {
            !files.fileExists(atPath: directory.appending(path: $0).path(percentEncoded: false))
        }
    }
}
