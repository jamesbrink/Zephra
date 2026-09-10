import Foundation
import ZephraCore
import ZephraSnapshot

extension WanBackend {
    /// Resolves the release, downloading it if it is not on this Mac, and returns the directory
    /// it is in. This is the release, not what gets loaded; `build` is next.
    ///
    /// Three places are looked at before anything is fetched: the packed variant, which makes
    /// the release unnecessary and may even have been deleted; the folder the user keeps models
    /// in; and the hub cache in either layout, which is read as a fallback and never written,
    /// so a Mac seeded by `make prefetch-wan` skips the twenty-four gigabytes.
    nonisolated(nonsending) public func ensureAvailable(
        _ descriptor: ModelDescriptor,
        locations: ModelLocations,
        acquisition: any ModelAcquisition,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        switch descriptor.source {
        case .localDirectory:
            let candidates = locations.builtCandidates(for: descriptor)
            if let built = candidates.first(where: { LocalSnapshot.wan.missingEntry(in: $0) == nil }) {
                return built
            }
            return try LocalSnapshot.wan.verified(
                candidates.first ?? locations.built(descriptor), descriptor: descriptor)
        case .huggingFace:
            if let packed = LocalSnapshot.wan.packedVariant(of: descriptor, in: locations) {
                return packed
            }
            if let here = LocalSnapshot.wanRelease.downloadedRelease(of: descriptor, in: locations) {
                return here
            }
            // Published ready-made, the variant is fetched instead of the release it is built
            // from; nil means the mirror has not got it, and the release comes next.
            if let prebuilt = try await acquisition.fetchPrebuilt(
                descriptor, into: locations, onProgress: onProgress)
            {
                return try LocalSnapshot.wan.verified(prebuilt, descriptor: descriptor)
            }
            let fetched = try await acquisition.fetch(
                descriptor, into: locations, release: nil, onProgress: onProgress)
            return try LocalSnapshot.wanRelease.verified(fetched, descriptor: descriptor)
        }
    }

    /// Packs the release at `localPath` into the variant `descriptor` names, unless it is the
    /// packed variant already, and returns the directory to load.
    nonisolated(nonsending) public func build(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        locations: ModelLocations,
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) async throws -> URL {
        guard descriptor.isBuiltLocally else { return localPath }
        if let packed = LocalSnapshot.wan.packedVariant(of: descriptor, in: locations) {
            return packed
        }
        try ModelDirectoryAccess.prepare(locations.root)
        do {
            return try WanSnapshotBuild.pack(
                release: localPath,
                into: locations.built(descriptor),
                descriptor: descriptor,
                onProgress: onProgress
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.loadFailed(error.readableMessage)
        }
    }
}
