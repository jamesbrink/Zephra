import Foundation
import MLX
import MLXNN
import ZephraMLX

/// Qwen-Image 2.1's autoencoder, `AutoencoderKLQwenImage21`: an **RGBA** picture to a
/// 64-channel latent at a sixteenth of its size, and back.
///
/// Four channels in and four out is 2.1's headline feature, and the one thing a three-channel
/// port would lose without failing. Pixels cross both doors in the range -1 to 1, channels
/// last, `[batch, height, width, 4]`; the latent crosses channels last too,
/// `[batch, height / 16, width / 16, 64]`, raw -- `QwenImage21LatentNormalization` is what
/// stands between that and the transformer's space, as it does in the reference pipeline.
///
/// The frame axis is gone. The reference is Wan's video autoencoder specialised to one frame:
/// its convolutions subclass `nn.Conv2d` and squeeze the axis away themselves, its encode runs
/// one chunk and its decode one, and every temporal convolution is behind a cache branch a
/// single chunk never takes. `QwenImage21CausalConv` states the whole of that argument.
///
/// The tree computes in the dtype its weights arrive in, and that is **float32**: the release
/// ships the autoencoder in float32 and every Zephra autoencoder stays there, since the decode
/// is a few seconds of a run and a bfloat16 decode of a 64-channel latent bands.
public final class QwenImage21Autoencoder: Module {
    @ModuleInfo(key: "encoder") var encoder: QwenImage21VAEEncoder
    @ModuleInfo(key: "decoder") var decoder: QwenImage21VAEDecoder
    @ModuleInfo(key: "quant_conv") var quantConv: QwenImage21CausalConv
    @ModuleInfo(key: "post_quant_conv") var postQuantConv: QwenImage21CausalConv

    public let configuration: QwenImage21VAEConfiguration

    public init(_ configuration: QwenImage21VAEConfiguration) {
        self.configuration = configuration
        _encoder.wrappedValue = QwenImage21VAEEncoder(configuration)
        _decoder.wrappedValue = QwenImage21VAEDecoder(configuration)
        _quantConv.wrappedValue = QwenImage21CausalConv(
            inputChannels: 2 * configuration.zDim, outputChannels: 2 * configuration.zDim,
            kernelSize: 1)
        _postQuantConv.wrappedValue = QwenImage21CausalConv(
            inputChannels: configuration.zDim, outputChannels: configuration.zDim,
            kernelSize: 1)
        super.init()
    }

    /// The dtype the autoencoder computes in: the one its weights hold.
    public var dtype: DType { quantConv.weight.dtype }

    /// Fills the tree from the release's `vae/*.safetensors` tensors. Every parameter must be
    /// covered exactly: a half missing a stage's weights would still run.
    public func load(weights: [String: MLXArray]) throws {
        try update(
            parameters: ModuleParameters.unflattened(QwenImage21VAEWeights.sanitized(weights)),
            verify: .all)
    }

    /// Encodes a picture, `[batch, height, width, 4]` in the range -1 to 1, to the latent
    /// distribution's **mode**, `[batch, height / 16, width / 16, zDim]`.
    ///
    /// The mode rather than a sample: the reference's `_encode_vae_image` asks for
    /// `sample_mode="argmax"`, which is `DiagonalGaussianDistribution.mode()`, which is the
    /// mean. So this takes the first half of what `quant_conv` writes and never reads the
    /// log-variance, and no seed enters an encode. Raw -- the pipeline normalises it with
    /// `QwenImage21LatentNormalization` before the transformer sees it.
    public func encode(_ picture: MLXArray) -> MLXArray {
        let moments = quantConv(encoder(picture.asType(dtype)))
        return moments[.ellipsis, 0..<configuration.zDim]
    }

    /// Decodes a latent in the autoencoder's own space, `[batch, height, width, zDim]`, to
    /// `[batch, height * 16, width * 16, 4]` clamped to -1 to 1, as the reference's `_decode`
    /// clamps it.
    ///
    /// With a `tile`, an edge in latent cells, the picture is decoded in overlapping tiles
    /// through `TiledDecode` and cross-faded where they meet, so the decode's peak is the
    /// tile's and not the picture's. The 1 x 1 `post_quant_conv`, `conv_in` and the mid block
    /// run first, whole, at the latent's size: the mid block attends over every cell, so only
    /// the upsampling stages after it are tiled (`QwenImage21VAEDecoder.head`).
    public func decode(_ latent: MLXArray, tile: Int? = nil) -> MLXArray {
        let x = postQuantConv(latent.asType(dtype))
        guard let tile, tile < max(x.dim(1), x.dim(2)) else { return clipped(decoder(x)) }
        return TiledDecode.run(
            decoder.head(x), tile: tile, scale: configuration.spatialCompression
        ) {
            clipped(decoder.tail($0))
        }
    }

    /// The whole picture in one pass, whatever its size: what a preview frame takes, and what
    /// `TiledDecodeTests` compares the tiled decode against.
    public func decodeUntiled(_ latent: MLXArray) -> MLXArray {
        decode(latent, tile: nil)
    }

    private func clipped(_ pixels: MLXArray) -> MLXArray {
        clip(pixels, min: -1, max: 1)
    }
}
