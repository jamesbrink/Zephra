import Foundation
import MLXNN

extension GroupNorm {
    /// The group norm every normalisation in the latent upsampler is: thirty-two groups with an
    /// affine pair, at PyTorch's default epsilon, grouped the way PyTorch groups.
    ///
    /// `pytorchCompatible` is the load-bearing argument. MLX's default grouping takes every
    /// thirty-second channel into a group; PyTorch takes contiguous runs of them. Both take the
    /// weights without complaint and only one matches the statistics these weights were trained
    /// against, which is why the parity fixture is dumped at a width where the two differ.
    static func ltx2Upsampler(channels: Int) -> GroupNorm {
        GroupNorm(groupCount: 32, dimensions: channels, eps: 1e-5, affine: true, pytorchCompatible: true)
    }
}
