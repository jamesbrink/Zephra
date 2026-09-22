import Foundation
import ZephraCore
import ZephraSnapshot

/// Getting the weights onto the disk. Split out of `ZImageBackend.swift` so loading and
/// generating read on their own, the way `+Availability` and `+Build` already do.
extension ZImageBackend {
    /// Resolves the descriptor's weights, downloading them if they are not on this Mac, and
    /// returns the directory to load from — or, for the four-bit variant, the release `build`
    /// packs next.
    ///
    /// What is already here is looked up rather than left to the vendored resolver, which knows
    /// only the layout `hf download` writes and would fetch a model Zephra itself downloaded
    /// again on every launch. Three places are looked at before anything is fetched: the packed
    /// variant, which makes the release unnecessary and may even have been deleted; the folder
    /// the user keeps models in; and the hub cache in either layout, read as a fallback and
    /// never written. `ZephraSnapshot`'s downloader does the fetching, and it is the only step
    /// that can report progress.
    nonisolated(nonsending) public func ensureAvailable(
        _ descriptor: ModelDescriptor,
        locations: ModelLocations,
        acquisition: any ModelAcquisition,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        switch descriptor.source {
        case .localDirectory:
            let candidates = locations.builtCandidates(for: descriptor)
            if let built = candidates.first(where: {
                LocalSnapshot.zImage.missingEntry(in: $0) == nil
            }) {
                return built
            }
            return try LocalSnapshot.zImage.verified(
                candidates.first ?? locations.built(descriptor), descriptor: descriptor)
        case .huggingFace:
            if descriptor.isBuiltLocally,
               let packed = LocalSnapshot.zImage.packedVariant(of: descriptor, in: locations)
            {
                return packed
            }
            let check = LocalSnapshot.zImage(for: descriptor)
            let here = check.downloadedRelease(of: descriptor, in: locations)
            if let here { return here }
            // The four-bit variant is published ready-made: it is fetched instead of the
            // release it is packed from, and nil means the mirror has not got it. The
            // eight-bit model has no mirror, and the call answers nil at once.
            if let prebuilt = try await acquisition.fetchPrebuilt(
                descriptor, into: locations, onProgress: onProgress)
            {
                return try LocalSnapshot.zImage.verified(prebuilt, descriptor: descriptor)
            }
            let fetched = try await acquisition.fetch(
                descriptor, into: locations, release: here, onProgress: onProgress)
            return try check.verified(fetched, descriptor: descriptor)
        }
    }
}
