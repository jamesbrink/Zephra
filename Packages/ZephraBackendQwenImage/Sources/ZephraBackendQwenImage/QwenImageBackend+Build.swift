import Foundation
import ZephraCore
import ZephraSnapshot

/// The build step: this family's download is never what gets loaded.
extension QwenImageBackend {
    /// Packs the release at `localPath` into the variant `descriptor` names, unless it is the
    /// packed variant already, and returns the directory to load.
    ///
    /// The adapter is not optional and not a setting: the base model wants fifty steps and real
    /// classifier-free guidance, and the four-step distillation is what makes it runnable on a
    /// Mac. It is merged here rather than at inference time, so the runtime never sees one.
    nonisolated(nonsending) public func build(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        locations: ModelLocations,
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) async throws -> URL {
        guard descriptor.isBuiltLocally else { return localPath }
        if let packed = LocalSnapshot.qwenImage.packedVariant(of: descriptor, in: locations) {
            return packed
        }
        let packed = locations.built(descriptor)
        do {
            return try QwenImageSnapshotBuild.pack(
                release: localPath,
                into: packed,
                descriptor: descriptor,
                adapters: descriptor.adapters.compactMap(locations.adapterFileOnDisk),
                onProgress: onProgress
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.loadFailed(error.readableMessage)
        }
    }
}
