import Foundation
import ZephraCore
import ZephraSnapshot

/// The build step, for the variant whose download is not what gets loaded.
///
/// Only the four-bit entry has one: the eight-bit model is published in the manifest format the
/// vendored loader reads, so its download loads as it stands, and `isBuiltLocally` is what tells
/// the two apart. Split out of `ZImageBackend.swift` so loading and generating read on their own.
extension ZImageBackend {
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
        if LocalSnapshot.zImage.missingEntry(in: packed) == nil { return packed }
        do {
            return try ZImageSnapshotBuild.pack(
                release: localPath, into: packed, descriptor: descriptor, onProgress: onProgress)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.loadFailed(error.readableMessage)
        }
    }
}
