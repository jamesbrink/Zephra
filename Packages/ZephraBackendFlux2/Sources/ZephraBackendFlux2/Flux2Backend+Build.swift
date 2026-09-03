import Flux2
import Foundation
import ZephraCore
import ZephraSnapshot

extension Flux2Backend {
    /// Resolves the release, downloading it into the hub cache if it is not there, and returns
    /// the snapshot directory. This is the release, not what gets loaded; `build` is next.
    nonisolated(nonsending) public func ensureAvailable(
        _ descriptor: ModelDescriptor,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        switch descriptor.source {
        case .localDirectory(let directory):
            return try LocalSnapshot.flux2.verified(directory, descriptor: descriptor)
        case .huggingFace(let repoID, let revision, let patterns):
            // Already built: the release is not needed, and may even have been deleted.
            let packed = Self.packedDirectory(for: descriptor)
            if LocalSnapshot.flux2.missingEntry(in: packed) == nil { return packed }
            do {
                return try await Flux2SnapshotDownload.snapshot(
                    repoID: repoID, revision: revision, patterns: patterns
                ) { progress in
                    onProgress(
                        DownloadProgressEvent(
                            completedFiles: progress.completedFiles,
                            totalFiles: progress.totalFiles,
                            fraction: progress.fraction,
                            bytesPerSecond: progress.bytesPerSecond))
                }
            } catch let error as CancellationError {
                throw error
            } catch {
                throw BackendError.downloadFailed(error.readableMessage)
            }
        }
    }

    /// Packs the release at `localPath` into the variant `descriptor` names, unless it is the
    /// packed variant already, and returns the directory to load.
    nonisolated(nonsending) public func build(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
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
