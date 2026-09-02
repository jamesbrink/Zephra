import Foundation
import ZephraCore

/// Answering "is this model on the machine?" from the disk alone. Split out of
/// `ZImageBackend.swift` so the loading and generating half of the backend reads on its own.
extension ZImageBackend {
    /// Says whether the weights are already on this Mac, reading the disk and nothing else.
    ///
    /// A Hugging Face model is looked up in the hub cache the loader itself would use; a local
    /// directory is checked for the entries the pipeline will open. Neither path downloads, and
    /// neither disturbs whatever is loaded, so a picker can label the whole catalog for free.
    nonisolated(nonsending) public func availability(
        of descriptor: ModelDescriptor
    ) async -> ModelAvailability {
        switch descriptor.source {
        case .localDirectory(let directory):
            guard let missing = ZImageLocalSnapshot.missingEntry(in: directory) else {
                return .available
            }
            return .missing(
                reason: """
                    \(descriptor.fullName) is not at \
                    \(directory.path(percentEncoded: false)): missing \(missing).
                    """
            )
        case .huggingFace(let repoID, _, _):
            guard ZImageHubCache.snapshot(of: repoID) != nil else {
                return .needsDownload(bytes: descriptor.downloadBytes)
            }
            return .available
        }
    }
}
