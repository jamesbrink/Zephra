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
        let files = FileManager.default
        for entry in requiredEntries {
            let path = directory.appending(path: entry).path(percentEncoded: false)
            guard files.fileExists(atPath: path) else {
                throw BackendError.downloadFailed(
                    "\(descriptor.fullName) is not at \(directory.path(percentEncoded: false)): missing \(entry)."
                )
            }
        }
        return directory
    }
}
