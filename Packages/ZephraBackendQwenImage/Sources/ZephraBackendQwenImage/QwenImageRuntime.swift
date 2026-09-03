import Foundation
import QwenImage

/// The one runtime knob that is Qwen-Image's own: the tile its VAE decodes in.
///
/// The allocator's limits and readings are process-wide and live in `MLXRuntime`; this is kept
/// apart because it is a variable of one pipeline's autoencoder, set by a host for the model
/// that is about to run.
public nonisolated enum QwenImageRuntime {
    /// The latent-space tile edge the VAE decode runs at, or nil for the exact untiled decode.
    ///
    /// Starts at whatever `ZEPHRA_VAE_TILE` said at launch, which is how the benchmark sets it.
    /// Assigning takes effect on the next decode; nothing reloads.
    public static var vaeTileSize: Int? {
        get { QwenImageAutoencoder.latentTile }
        set { QwenImageAutoencoder.latentTile = newValue }
    }
}
