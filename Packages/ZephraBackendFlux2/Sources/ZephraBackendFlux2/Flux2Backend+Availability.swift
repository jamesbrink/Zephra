import Foundation
import ZephraCore
import ZephraSnapshot

extension Flux2Backend {
    /// Whether `descriptor` can be loaded now, answered from the disk alone.
    ///
    /// Three answers, because three things can be true of this family. The packed variant is
    /// there, so it loads. The release is in the hub cache but the variant is not, so loading
    /// means a build and no network. Or neither is there, and loading means both.
    nonisolated(nonsending) public func availability(
        of descriptor: ModelDescriptor,
        locations: ModelLocations
    ) async -> ModelAvailability {
        switch descriptor.source {
        case .localDirectory(let directory):
            if let missing = LocalSnapshot.flux2.missingEntry(in: directory) {
                return .missing(reason: "Not built yet: \(missing) is missing. Run `make quantize-flux2`.")
            }
            return .available
        case .huggingFace(let repoID, let revision, _):
            if LocalSnapshot.flux2.missingEntry(in: Self.packedDirectory(for: descriptor)) == nil {
                return .available
            }
            guard let release = HubCache.snapshot(of: repoID, revision: revision),
                  LocalSnapshot.flux2Release.missingEntry(in: release) == nil
            else {
                return .needsDownloadAndBuild(bytes: descriptor.downloadBytes)
            }
            return .needsBuild
        }
    }
}
