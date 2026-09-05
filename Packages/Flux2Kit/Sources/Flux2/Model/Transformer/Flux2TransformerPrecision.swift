import Foundation
import MLX

/// What the transformer's activations are held in.
///
/// bfloat16 by default: the weights are, the reference runs in it, and at a 4096-token image
/// the attention over a float32 stream falls off MLX's fused kernel and costs a 2 GB score
/// matrix per block. The dtype is the host's choice, handed to `Flux2Pipeline.loadModel(at:
/// activation:)` and applied there once — to the packer's float32 scales, the noise, the text
/// and the reference tokens — so nothing in the stream can widen it by accident. The kit reads
/// no environment variable and asks no device; a host that runs the stream float32 (the
/// workaround for mlx-swift up to 0.31.6 miscompiling a bfloat16 split-K matmul on M5-class
/// GPUs at the single block's output shape; see `Flux2ParallelAttention`) decides that at its
/// own edge.
public enum Flux2TransformerPrecision {
    /// The dtype a pipeline casts its latents and text to unless told otherwise.
    public static let defaultActivation: DType = .bfloat16
}
