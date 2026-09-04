import Foundation
import ZephraCore
import ZephraSnapshot

/// Answering "is this model on the machine?" from the disk alone. Split out of
/// `ZImageBackend.swift` so the loading and generating half of the backend reads on its own.
extension ZImageBackend {
    /// Says whether the weights are already on this Mac, reading the disk and nothing else.
    ///
    /// Four answers, because the family has two shapes of model. The eight-bit variant is
    /// published in the format the loader reads, so its download is either here or a download
    /// away. The four-bit variant is packed here from the bf16 release, so it is here, or a
    /// build away, or a download and a build away. Nothing downloads and nothing disturbs what
    /// is loaded, so a picker can label the whole catalog for free.
    nonisolated(nonsending) public func availability(
        of descriptor: ModelDescriptor,
        locations: ModelLocations
    ) async -> ModelAvailability {
        switch descriptor.source {
        case .localDirectory:
            let candidates = locations.builtCandidates(for: descriptor)
            guard candidates.allSatisfy({ LocalSnapshot.zImage.missingEntry(in: $0) != nil })
            else { return .available }
            let directory = candidates[0]
            let missing = LocalSnapshot.zImage.missingEntry(in: directory) ?? "its weights"
            return .missing(
                reason: """
                    \(descriptor.fullName) is not at \
                    \(directory.path(percentEncoded: false)): missing \(missing).
                    """
            )
        case .huggingFace:
            if descriptor.isBuiltLocally,
               LocalSnapshot.zImage.packedVariant(of: descriptor, in: locations) != nil
            {
                return .available
            }
            let release = LocalSnapshot.zImage(for: descriptor)
                .downloadedRelease(of: descriptor, in: locations)
            if release != nil, locations.missingAdapters(of: descriptor).isEmpty {
                return descriptor.isBuiltLocally ? .needsBuild : .available
            }
            let bytes = locations.bytesToFetch(for: descriptor, releasePresent: release != nil)
            return descriptor.isBuiltLocally
                ? .needsDownloadAndBuild(bytes: bytes)
                : .needsDownload(bytes: bytes)
        }
    }
}
