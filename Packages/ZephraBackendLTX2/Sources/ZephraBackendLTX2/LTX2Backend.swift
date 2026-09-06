import Foundation
import ZephraCore
import ZephraMLX

/// Runs LTX-2.5 models through Zephra's own MLX pipeline.
///
/// The instance is deliberately not Sendable: it will own an `LTX2Pipeline`, which holds MLX
/// arrays that must stay on one thread. The engine layer confines it to a serial executor.
///
/// The class is explicitly `nonisolated` so that it compiles the same way whichever target
/// links it. The app builds with default MainActor isolation, and under that setting an
/// inferred-isolated backend could not hand its non-Sendable pipeline to the pipeline's own
/// methods.
public nonisolated final class LTX2Backend: ImageGenerationBackend {
    /// The model family this backend serves.
    public static let backendID = BackendID.ltx2

    /// The descriptor identifier currently in memory, or nil when nothing is loaded.
    public private(set) var loadedModelID: String?

    /// How the loaded weights are held: what the last load did.
    public private(set) var loadedResidency: WeightResidency?

    /// The switches the composition root read once: the stream's dtype override, the stream
    /// depth and how often a preview frame is made.
    let environment: InferenceEnvironment
    /// The VAE tile the engine set for the run about to start; see `LTX2BackendFactory`. The
    /// video decoder does not tile yet, so the value is read and left alone.
    let tile: VAETileSetting

    /// Creates an idle backend running under `environment`. No weights are touched until
    /// `ensureAvailable` is called.
    public init(environment: InferenceEnvironment, tile: VAETileSetting) {
        self.environment = environment
        self.tile = tile
    }

    /// An idle backend under the default switches, for tests that only ask about the disk.
    public convenience init() {
        self.init(environment: InferenceEnvironment(), tile: VAETileSetting())
    }

    /// Reads the packed weights at `localPath` into memory. The pipeline lands with the kit;
    /// until then a load says so rather than pretending.
    nonisolated(nonsending) public func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        residency: WeightResidency,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        throw BackendError.loadFailed("LTX-2.5's pipeline is not wired into this build yet.")
    }

    /// Makes a clip from `settings`.
    nonisolated(nonsending) public func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> GeneratedMedia {
        throw BackendError.loadFailed("No model is loaded.")
    }

    /// Releases the weights and the scratch memory MLX kept for them.
    public func unload() {
        loadedModelID = nil
        loadedResidency = nil
    }
}
