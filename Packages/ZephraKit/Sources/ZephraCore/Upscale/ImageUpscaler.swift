import Foundation

/// A network that makes a picture larger. A post-process beside the diffusion backends, not
/// one of them: it needs no model loaded, holds a few megabytes, and takes finished pixels
/// rather than a prompt.
///
/// Implementations are NOT Sendable and run on the engine's serial inference executor, the
/// same queue a generation runs on, so two Metal jobs never overlap. The async requirement is
/// `nonisolated(nonsending)` for the reason `ImageGenerationBackend`'s are: an actor that owns
/// an upscaler could not otherwise call it.
public protocol ImageUpscaler: AnyObject {
    /// PNG bytes in, PNG bytes out at `request.factor` times each edge. Must check Task
    /// cancellation between tiles so a person can stop it.
    nonisolated(nonsending) func upscale(
        _ png: Data,
        _ request: UpscaleRequest,
        onProgress: @escaping (UpscaleProgressEvent) -> Void
    ) async throws -> Data
    /// Releases the weights and any scratch memory.
    func unload()
}
