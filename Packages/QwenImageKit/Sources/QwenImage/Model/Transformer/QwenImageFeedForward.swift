import Foundation
import MLX
import MLXNN

/// The projection at the front of a block's feed-forward network.
///
/// Its own type because the reference wraps the projection inside an activation module, so the
/// checkpoint names the weight `net.0.proj`.
final class QwenImageGELUProjection: Module, UnaryLayer {
    @ModuleInfo(key: "proj") var projection: Linear

    init(_ input: Int, _ output: Int) {
        _projection.wrappedValue = Linear(input, output, bias: true)
    }

    /// GELU's **tanh** approximation, which is what `gelu-approximate` means in the reference.
    /// MLX's plain `gelu` is the exact erf form and differs by enough to matter.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        geluApproximate(projection(x))
    }
}

/// A block's feed-forward network: widen fourfold, gate with GELU, narrow back.
///
/// `net` is an array with a hole in the middle because the reference builds it as
/// `Sequential(GELU(proj), Dropout, Linear)` and the checkpoint numbers the two parameterised
/// layers `0` and `2`. MLX turns those numeric segments into array positions when it unflattens
/// weights, so the module has to be an array too, with the dropout's slot standing empty.
final class QwenImageFeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "net") var net: [Module]

    init(dim: Int, expansion: Int = 4) {
        _net.wrappedValue = [
            QwenImageGELUProjection(dim, dim * expansion),
            Identity(),
            Linear(dim * expansion, dim, bias: true),
        ]
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        guard let input = net[0] as? QwenImageGELUProjection, let output = net[2] as? Linear
        else {
            preconditionFailure("the feed-forward's slots 0 and 2 must be its two projections")
        }
        return output(input(x))
    }
}
