import Flux2
import Foundation
import ZephraCore
import ZephraSnapshot

extension Flux2Backend {
    /// Resolves the release, downloading it if it is not on this Mac, and returns the directory
    /// it is in. This is the release, not what gets loaded; `build` is next.
    ///
    /// Three places are looked at before anything is fetched: the packed variant, which makes
    /// the release unnecessary and may even have been deleted; the folder the user keeps models
    /// in; and the hub cache in either layout, which is read as a fallback and never written,
    /// so a Mac seeded by `make prefetch-flux2` skips the sixteen gigabytes.
    nonisolated(nonsending) public func ensureAvailable(
        _ descriptor: ModelDescriptor,
        locations: ModelLocations,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        switch descriptor.source {
        case .localDirectory:
            let candidates = locations.builtCandidates(for: descriptor)
            if let built = candidates.first(where: { LocalSnapshot.flux2.missingEntry(in: $0) == nil })
            {
                return built
            }
            return try LocalSnapshot.flux2.verified(
                candidates.first ?? locations.built(descriptor), descriptor: descriptor)
        case .huggingFace(let repoID, let revision, _):
            let packed = locations.built(descriptor)
            if LocalSnapshot.flux2.missingEntry(in: packed) == nil { return packed }
            if let release = Self.release(repoID: repoID, revision: revision, in: locations) {
                return release
            }
            let fetched = try await ModelDownloader().fetch(
                descriptor, into: locations, onProgress: onProgress)
            return try LocalSnapshot.flux2Release.verified(fetched, descriptor: descriptor)
        }
    }

    /// The klein release as it sits on this Mac, or nil when it is not here: the app's own
    /// downloads folder first, then the hub cache.
    static func release(repoID: String, revision: String, in locations: ModelLocations) -> URL? {
        let downloads = locations.downloads(repoID: repoID)
        if LocalSnapshot.flux2Release.missingEntry(in: downloads) == nil,
           HubSnapshotCheck.incompleteFiles(in: downloads).isEmpty
        {
            return downloads
        }
        if let cached = HubCache.snapshot(of: repoID, revision: revision),
           LocalSnapshot.flux2Release.missingEntry(in: cached) == nil
        {
            return cached
        }
        return nil
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
        let packed = locations.built(descriptor)
        if LocalSnapshot.flux2.missingEntry(in: packed) == nil { return packed }
        do {
            return try Flux2SnapshotBuild.pack(
                release: localPath,
                into: packed,
                sourceName: Self.sourceName(of: descriptor),
                quantization: descriptor.quantization,
                onProgress: onProgress
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.loadFailed(error.readableMessage)
        }
    }

    private static func sourceName(of descriptor: ModelDescriptor) -> String {
        if case .huggingFace(let repoID, _, _) = descriptor.source { return repoID }
        return descriptor.id
    }
}
