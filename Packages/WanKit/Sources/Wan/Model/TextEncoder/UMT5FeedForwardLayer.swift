import Foundation
import MLX
import MLXNN

/// The second half of a UMT5 block, `layer.1` in the checkpoint: a scale-only RMS norm, the
/// gated feed-forward, and the residual add.
final class UMT5FeedForwardLayer: Module, UnaryLayer {
    @ModuleInfo(key: "DenseReluDense") var feedForward: UMT5FeedForward
    @ModuleInfo(key: "layer_norm") var norm: RMSNorm

    init(_ configuration: UMT5Configuration) {
        _feedForward.wrappedValue = UMT5FeedForward(configuration)
        _norm.wrappedValue = RMSNorm(dimensions: configuration.dModel, eps: configuration.layerNormEpsilon)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        x + feedForward(norm(x))
    }
}
