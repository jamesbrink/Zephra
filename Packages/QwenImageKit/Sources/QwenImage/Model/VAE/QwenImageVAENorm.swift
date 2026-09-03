import Foundation
import MLX
import MLXNN

/// The autoencoder's normalisation: unit-length across channels, then scaled.
///
/// Not the usual RMS norm. The reference L2-normalises across the channel axis, multiplies by
/// the square root of the channel count, and then by a learned gain — which comes to the same
/// family of operation but is written differently enough that copying an RMSNorm here would be
/// quietly wrong.
final class QwenImageVAENorm: Module, UnaryLayer {
    @ModuleInfo(key: "gamma") var gamma: MLXArray

    private let scale: Float

    init(_ channels: Int, imagesOnly: Bool) {
        // The stored gain keeps its broadcast axes: three for a video tensor, two for an image.
        let shape = imagesOnly ? [channels, 1, 1] : [channels, 1, 1, 1]
        _gamma.wrappedValue = MLXArray.ones(shape)
        scale = sqrt(Float(channels))
    }

    /// Normalises `x`, which is `[batch, height, width, channels]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let magnitude = MLX.sqrt(MLX.sum(x * x, axis: -1, keepDims: true))
        let normalized = x / MLX.maximum(magnitude, MLXArray(Float(1e-12)))
        return normalized * scale * gamma.reshaped([-1])
    }
}
