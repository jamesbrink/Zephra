import Foundation
import MLX

/// What the transformer's activations are held in.
///
/// bfloat16 by default: the weights are, the reference runs in it, and at a 4096-token image a
/// float32 stream falls off MLX's fused attention kernel and costs a score matrix per block.
///
/// The dtype is the host's choice, handed to the pipeline's load and applied there once — to the
/// packer's float32 scales, the noise and the text — so nothing in the stream can widen it by
/// accident. The kit reads no environment variable and asks no device; a host that wants a
/// float32 stream decides that at its own edge.
public enum QwenImage21TransformerPrecision {
    /// The dtype a pipeline casts its latents and text to unless told otherwise.
    public static let defaultActivation: DType = .bfloat16
}
