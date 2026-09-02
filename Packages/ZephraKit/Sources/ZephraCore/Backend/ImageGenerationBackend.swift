import Foundation

/// One inference engine for one family of models. Implementations are NOT Sendable and are
/// confined to a single serial executor owned by the engine layer.
///
/// The async requirements are `nonisolated(nonsending)` so they run on the caller's executor.
/// Without it, an actor that owns a backend cannot call these methods at all: passing an
/// actor-isolated, non-Sendable instance into a `@concurrent` async function is a data race the
/// Swift 6 compiler rejects. Conformances are written as ordinary `async` methods either way.
public protocol ImageGenerationBackend: AnyObject {
    /// The family this implementation serves, matched against a descriptor's backend.
    static var backendID: BackendID { get }

    /// The descriptor identifier currently held in memory, or nil when nothing is loaded.
    var loadedModelID: String? { get }

    /// Whether the weights for `descriptor` are already on this Mac. Reads the disk and nothing
    /// else: it must never download, and it must leave whatever is loaded exactly as it was, so
    /// a picker can label every model in the catalog without committing to any of them.
    nonisolated(nonsending) func availability(
        of descriptor: ModelDescriptor
    ) async -> ModelAvailability

    /// Ensures weights are on disk, downloading if needed. Returns the local snapshot directory.
    nonisolated(nonsending) func ensureAvailable(
        _ descriptor: ModelDescriptor,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL

    /// Loads weights from `localPath` into memory. Progress handler is intentionally not
    /// @Sendable (mirrors the underlying libraries).
    nonisolated(nonsending) func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws

    /// Returns PNG bytes. Must honour Task cancellation between denoising steps.
    nonisolated(nonsending) func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> Data

    /// Releases the loaded weights and any scratch memory.
    func unload()
}
