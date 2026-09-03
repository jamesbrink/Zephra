import Foundation
import MLX

/// What the transformer's activations are held in.
///
/// bfloat16 by default: the weights are, the reference runs in it, and at a 4096-token image
/// the attention over a float32 stream falls off MLX's fused kernel and costs a 2 GB score
/// matrix per block. `ZEPHRA_DIT_DTYPE=f32` runs the stream in float32 instead, which is the
/// workaround for mlx-swift up to 0.31.6 miscompiling a bfloat16 split-K matmul on M5-class
/// GPUs at the single block's output shape; see `Flux2ParallelAttention`.
public enum Flux2TransformerPrecision {
    /// The dtype the pipeline casts its latents and text to before the first block.
    public static let activation: DType =
        ProcessInfo.processInfo.environment["ZEPHRA_DIT_DTYPE"] == "f32" ? .float32 : .bfloat16
}
