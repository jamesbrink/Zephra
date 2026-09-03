import Foundation
import MLX
import MLXFast
import MLXNN

/// The autoencoder's one attention block, in the middle of the decoder.
///
/// Every pixel attends to every other, so at 1024 pixels this runs over a 128x128 latent —
/// 16,384 positions — and is the decode's memory high-water mark. It is the reason tiled
/// decoding exists.
final class QwenImageVAEAttentionBlock: Module {
    @ModuleInfo(key: "norm") var norm: QwenImageVAENorm
    @ModuleInfo(key: "to_qkv") var qkv: Conv2d
    @ModuleInfo(key: "proj") var projection: Conv2d

    private let channels: Int

    init(_ channels: Int) {
        self.channels = channels
        // Two broadcast axes here, not three: the reference builds this norm in image mode.
        _norm.wrappedValue = QwenImageVAENorm(channels, imagesOnly: true)
        _qkv.wrappedValue = Conv2d(
            inputChannels: channels, outputChannels: channels * 3, kernelSize: 1)
        _projection.wrappedValue = Conv2d(
            inputChannels: channels, outputChannels: channels, kernelSize: 1)
    }

    /// Attends over `x`, `[batch, height, width, channels]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let (batch, height, width) = (x.shape[0], x.shape[1], x.shape[2])
        let projected = qkv(norm(x)).reshaped([batch, height * width, 3, channels])
        // One head over the whole channel width, which is what a single-head 1x1 attention is.
        let queries = projected[0..., 0..., 0].expandedDimensions(axis: 1)
        let keys = projected[0..., 0..., 1].expandedDimensions(axis: 1)
        let values = projected[0..., 0..., 2].expandedDimensions(axis: 1)

        let attended = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values,
            scale: 1 / sqrt(Float(channels)), mask: nil
        )
        .squeezed(axis: 1)
        .reshaped([batch, height, width, channels])

        return projection(attended) + x
    }
}
