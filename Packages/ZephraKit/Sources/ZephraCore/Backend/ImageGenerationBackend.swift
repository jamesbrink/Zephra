import Foundation

/// One inference engine for one family of models. Implementations are NOT Sendable and are
/// confined to a single serial executor owned by the engine layer.
public protocol ImageGenerationBackend: AnyObject {
    /// The family this implementation serves, matched against a descriptor's backend.
    static var backendID: BackendID { get }

    /// The descriptor identifier currently held in memory, or nil when nothing is loaded.
    var loadedModelID: String? { get }

    /// Ensures weights are on disk, downloading if needed. Returns the local snapshot directory.
    func ensureAvailable(
        _ descriptor: ModelDescriptor,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL

    /// Loads weights from `localPath` into memory. Progress handler is intentionally not
    /// @Sendable (mirrors the underlying libraries).
    func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws

    /// Returns PNG bytes. Must honour Task cancellation between denoising steps.
    func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> Data

    /// Releases the loaded weights and any scratch memory.
    func unload()
}
