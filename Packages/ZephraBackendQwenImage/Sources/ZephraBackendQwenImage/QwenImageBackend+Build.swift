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
        // Every adapter, or no build: a base model packed without its four-step distillation
        // would load under this descriptor and be wrong in a way that does not announce
        // itself. An adapter that was here at `ensureAvailable` and is not now — deleted, or
        // on a volume that has gone — is a model to choose again, which fetches it.
        let adapters = descriptor.adapters.compactMap(locations.adapterFileOnDisk)
        guard adapters.count == descriptor.adapters.count else {
            throw BackendError.loadFailed(
                "\(descriptor.fullName)'s adapter is no longer on this Mac. Choose the model again to fetch it.")
        }
        do {
            return try QwenImageSnapshotBuild.pack(
                release: localPath,
                into: packed,
                descriptor: descriptor,
                adapters: adapters,
                onProgress: onProgress
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.loadFailed(error.readableMessage)
        }
    }
}
