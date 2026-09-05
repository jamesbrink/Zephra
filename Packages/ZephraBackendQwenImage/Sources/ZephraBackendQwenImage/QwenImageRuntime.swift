import Foundation
import QwenImage

/// The runtime knobs that are Qwen-Image's own: the tile its VAE decodes in, and how far ahead
/// a streamed load reads.
///
/// The allocator's limits and readings are process-wide and live in `MLXRuntime`; these are
/// kept apart because each is a variable of one pipeline, set by a host for the model that is
/// about to run.
public nonisolated enum QwenImageRuntime {
    /// Layers a streamed load reads ahead of the one running, for the next `load`.
    ///
    /// Starts at whatever `ZEPHRA_STREAM_DEPTH` said at launch, which is how the benchmark
    /// sweeps it, and at two otherwise. Read when a model is loaded streamed; a change after
    /// that waits for the next load.
    nonisolated(unsafe) public static var streamDepth: Int = {
        ProcessInfo.processInfo.environment["ZEPHRA_STREAM_DEPTH"].flatMap(Int.init) ?? 2
    }()

    /// The latent-space tile edge the VAE decode runs at, or nil for the exact untiled decode.
    ///
    /// Starts at whatever `ZEPHRA_VAE_TILE` said at launch, which is how the benchmark sets it.
    /// Assigning takes effect on the next decode; nothing reloads.
    public static var vaeTileSize: Int? {
        get { QwenImageAutoencoder.latentTile }
        set { QwenImageAutoencoder.latentTile = newValue }
    }
}
