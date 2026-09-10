import Foundation
import MLX
import MLXNN

/// The patch embedding: a convolution whose kernel and stride are the patch, so each
/// `1 x 2 x 2` cell of the latent becomes one token of the stream.
///
/// A `Conv3d` and nothing more, so its parameters are `patch_embedding.weight` and
/// `patch_embedding.bias`, the checkpoint's own names. The latent arrives as the reference
/// takes it, `[batch, channels, frames, height, width]`, and is turned channels-last for MLX's
/// convolution here; the kernel is stored `[out, kd, kh, kw, in]`, MLX's order, and
/// `kernel(fromTorch:)` is how a checkpoint's `[out, in, kd, kh, kw]` gets there at load.
final class WanPatchEmbedding: Conv3d {
    /// Cells one token covers, as frames, rows, columns.
    let patch: [Int]

    init(inChannels: Int, dim: Int, patch: [Int]) {
        self.patch = patch
        let size = IntOrTriple(arrayLiteral: patch[0], patch[1], patch[2])
        super.init(inputChannels: inChannels, outputChannels: dim, kernelSize: size, stride: size)
    }

    /// `[batch, channels, frames, height, width]` to `[batch, tokens, dim]`, tokens in frame,
    /// row, column order, which is the reference's `flatten(2).transpose(1, 2)`.
    func tokens(of latent: MLXArray) -> MLXArray {
        let embedded = self(latent.transposed(0, 2, 3, 4, 1))
        return embedded.reshaped([embedded.shape[0], -1, embedded.shape[4]])
    }

    /// How many tokens a latent of that shape makes along each axis.
    func grid(of latent: MLXArray) -> (frames: Int, height: Int, width: Int) {
        (latent.shape[2] / patch[0], latent.shape[3] / patch[1], latent.shape[4] / patch[2])
    }

    /// A kernel in PyTorch's `[out, in, kd, kh, kw]` order as MLX's `[out, kd, kh, kw, in]`.
    static func kernel(fromTorch weight: MLXArray) -> MLXArray {
        weight.transposed(0, 2, 3, 4, 1)
    }
}
