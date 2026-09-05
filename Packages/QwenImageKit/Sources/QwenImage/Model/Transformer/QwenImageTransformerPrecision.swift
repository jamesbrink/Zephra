import Foundation
import MLX

/// What the transformer's activations are held in.
///
/// bfloat16 by default: the weights are, the reference runs in it, and at a 4096-token image
/// the attention over a float32 stream falls off MLX's fused kernel and costs a 2 GB score
/// matrix per block. The dtype is the host's choice, handed to
/// `QwenImagePipeline.loadModel(at:activation:streaming:)` and applied there once — to the
/// packer's float32 scales before a stream is attached, and by `generate` to the noise and the
/// conditioning before the first block — so nothing in the stream can widen it by accident;
/// any one of those left in float32 is how this family ran in float32 by accident. The kit
/// reads no environment variable: `ZEPHRA_DIT_DTYPE=f32` is read once at the composition root
/// and arrives here as a value.
public enum QwenImageTransformerPrecision {
    /// The dtype a pipeline casts its latents and text to unless told otherwise.
    public static let defaultActivation: DType = .bfloat16
}
