import Foundation
import ZephraCore
import ZephraSnapshot

extension Flux2Backend {
    /// Whether `descriptor` can be loaded now, answered from the disk alone.
    ///
    /// Three answers, because three things can be true of this family. The packed variant is
    /// there, so it loads. The release is on this Mac but the variant is not, so loading means
    /// a build and no network. Or neither is there, and loading means both.
    nonisolated(nonsending) public func availability(
        of descriptor: ModelDescriptor,
        locations: ModelLocations
    ) async -> ModelAvailability {
        switch descriptor.source {
        case .localDirectory:
            let candidates = locations.builtCandidates(for: descriptor)
            guard candidates.allSatisfy({ LocalSnapshot.flux2.missingEntry(in: $0) != nil })
            else { return .available }
            let missing = LocalSnapshot.flux2.missingEntry(in: candidates[0]) ?? "its weights"
            return .missing(reason: "Not built yet: \(missing) is missing. Run `make quantize-flux2`.")
        case .huggingFace:
            if LocalSnapshot.flux2.missingEntry(in: locations.built(descriptor)) == nil {
                return .available
            }
            let release = LocalSnapshot.flux2Release.downloadedRelease(of: descriptor, in: locations)
            if release != nil, locations.missingAdapters(of: descriptor).isEmpty {
                return .needsBuild
            }
            return .needsDownloadAndBuild(
                bytes: locations.bytesToFetch(for: descriptor, releasePresent: release != nil))
        }
    }
}
