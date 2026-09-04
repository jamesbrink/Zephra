import Flux2
import Foundation
import ZephraCore
import ZephraSnapshot

extension Flux2Backend {
    /// Resolves the release, downloading it into the hub cache if it is not there, and returns
    /// the snapshot directory. This is the release, not what gets loaded; `build` is next.
    ///
    /// The cache is asked first, in both of its layouts, so a release the app downloaded is
    /// found on the next launch without a request; the download itself, with its retries, is
    /// `Flux2Backend+Download.swift`.
    nonisolated(nonsending) public func ensureAvailable(
        _ descriptor: ModelDescriptor,
        locations: ModelLocations,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        switch descriptor.source {
        case .localDirectory(let directory):
            return try LocalSnapshot.flux2.verified(directory, descriptor: descriptor)
        case .huggingFace(let repoID, let revision, let patterns):
            // Already built: the release is not needed, and may even have been deleted.
            let packed = Self.packedDirectory(for: descriptor)
            if LocalSnapshot.flux2.missingEntry(in: packed) == nil { return packed }
            if let cached = HubCache.snapshot(of: repoID, revision: revision),
               LocalSnapshot.flux2Release.missingEntry(in: cached) == nil
            {
                return cached
            }
            let release = try await download(
                repoID, revision: revision, patterns: patterns, onProgress: onProgress)
            return try LocalSnapshot.flux2Release.verified(release, descriptor: descriptor)
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
        let packed = Self.packedDirectory(for: descriptor)
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
