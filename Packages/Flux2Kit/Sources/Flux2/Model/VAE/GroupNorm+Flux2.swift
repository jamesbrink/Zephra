import Foundation
import MLXNN

extension GroupNorm {
    /// The epsilon every normalisation in this autoencoder uses.
    ///
    /// diffusers hard-codes it as `resnet_eps` when it builds the `Encoder` and the `Decoder`, so
    /// it is nowhere in `vae/config.json` and cannot be read from there. MLX defaults to 1e-5,
    /// which is close enough that a build with the wrong one still produces a plausible image.
    static let flux2Eps: Float = 1e-6

    /// A group norm shaped the way the checkpoint's weights expect.
    ///
    /// `pytorchCompatible` is the load-bearing argument. MLX's default grouping takes every
    /// `groupCount`-th channel into a group; PyTorch takes contiguous runs of them. Both
    /// normalise, both take the same weights without complaint, and only one matches the
    /// statistics these weights were trained against.
    static func flux2(channels: Int, groups: Int) -> GroupNorm {
        GroupNorm(
            groupCount: groups, dimensions: channels, eps: flux2Eps, affine: true,
            pytorchCompatible: true)
    }
}
