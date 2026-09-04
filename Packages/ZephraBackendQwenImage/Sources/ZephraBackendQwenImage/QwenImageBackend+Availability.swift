import Foundation
import ZephraCore
import ZephraSnapshot

/// Answering "is this model on the machine?" from the disk alone. Split out of
/// `QwenImageBackend.swift` so the loading and generating half of the backend reads on its own.
extension QwenImageBackend {
    /// Whether the weights are on this Mac, read from the disk alone.
    ///
    /// Three answers, because three things can be true. The packed variant is there, so it
    /// loads. The release and its adapter are here but the variant is not, so loading means a
    /// build and no network. Or they are not, and loading means both — which for this model is
    /// fifty-nine gigabytes, so saying it up front rather than starting is the whole point.
    nonisolated(nonsending) public func availability(
        of descriptor: ModelDescriptor,
        locations: ModelLocations
    ) async -> ModelAvailability {
        switch descriptor.source {
        case .localDirectory:
            let candidates = locations.builtCandidates(for: descriptor)
            guard candidates.allSatisfy({ LocalSnapshot.qwenImage.missingEntry(in: $0) != nil })
            else { return .available }
            let missing = LocalSnapshot.qwenImage.missingEntry(in: candidates[0]) ?? "its weights"
            return .missing(
                reason: "Not built yet: \(missing) is missing. Run `make quantize-qwen`.")
        case .huggingFace:
            if LocalSnapshot.qwenImage.packedVariant(of: descriptor, in: locations) != nil {
                return .available
            }
            let release = LocalSnapshot.qwenImageRelease.downloadedRelease(
                of: descriptor, in: locations)
            if release != nil, locations.missingAdapters(of: descriptor).isEmpty {
                return .needsBuild
            }
            return .needsDownloadAndBuild(
                bytes: locations.bytesToFetch(for: descriptor, releasePresent: release != nil))
        }
    }
}
