import Foundation
import MLX

/// What the transformer's activations are held in.
///
/// bfloat16 by default: the weights are, the reference runs in it, and at a 4096-token image
/// the attention over a float32 stream falls off MLX's fused kernel and costs a 2 GB score
/// matrix per block. The pipeline casts the noise and the conditioning to this before the
/// first step, and the loader casts the packer's float32 scales to it before anything
/// evaluates them; any one of those left in float32 widens the whole stream after it, which
/// is how this family ran in float32 by accident. `ZEPHRA_DIT_DTYPE=f32` runs the stream in
/// float32 instead, the same switch klein reads.
public enum QwenImageTransformerPrecision {
    /// The dtype the pipeline casts its latents and text to before the first block.
    public static let activation: DType =
        ProcessInfo.processInfo.environment["ZEPHRA_DIT_DTYPE"] == "f32" ? .float32 : .bfloat16
}
