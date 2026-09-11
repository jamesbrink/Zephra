import Foundation
import MLX
import MLXNN

/// LTX-2.5's audio autoencoder, the decoding half: a packed audio latent to a stereo
/// log-mel spectrogram the vocoder turns into sound.
///
/// `conv_in`, two middle blocks, then the levels from the widest down with a doubling
/// upsampler between each pair, then pixel-norm, SiLU and `conv_out` to two channels, cropped
/// to `4 * frames - 3` mel frames and the layout's bins. Activations are channels-last,
/// `[batch, time, mel, channels]`, from the first convolution to the last. The encoder is not
/// ported: nothing conditions audio, and the reference's own pipelines never encode any.
///
/// Computes in whatever dtype its weights hold; the loader casts them to float32, as it does
/// the vocoder's, since the spectrogram feeds a hundred convolutions downstream.
public final class LTX2AudioDecoder: Module {
    @ModuleInfo(key: "conv_in") var convIn: LTX2AudioCausalConv2d
    @ModuleInfo(key: "mid") var middle: LTX2AudioMiddle
    @ModuleInfo(key: "up") var levels: [LTX2AudioLevel]
    @ModuleInfo(key: "conv_out") var convOut: LTX2AudioCausalConv2d
    /// The packed latent's statistics, the transformer's tokens denormalised through.
    @ModuleInfo(key: "per_channel_statistics") public private(set) var statistics: LTX2AudioStatistics

    public let layout: LTX2AudioDecoderLayout

    public init(_ layout: LTX2AudioDecoderLayout = .ltx25) {
        self.layout = layout
        let top = layout.multipliers.count - 1
        let widest = layout.channels(at: top)
        _convIn.wrappedValue = LTX2AudioCausalConv2d(inputChannels: layout.latentChannels, outputChannels: widest)
        _middle.wrappedValue = LTX2AudioMiddle(channels: widest, eps: layout.normEpsilon)
        var levels: [LTX2AudioLevel] = []
        var incoming = widest
        for level in stride(from: top, through: 0, by: -1) {
            let width = layout.channels(at: level)
            levels.insert(
                LTX2AudioLevel(
                    inputChannels: incoming, channels: width, blocks: layout.blocksPerLevel,
                    upsamples: level != 0, eps: layout.normEpsilon),
                at: 0)
            incoming = width
        }
        _levels.wrappedValue = levels
        _convOut.wrappedValue = LTX2AudioCausalConv2d(
            inputChannels: layout.channels(at: 0), outputChannels: layout.outputChannels)
        _statistics.wrappedValue = LTX2AudioStatistics(width: layout.packedChannels)
    }

    /// The dtype the decoder computes in: the one its weights hold.
    public var dtype: DType { convIn.conv.weight.dtype }

    /// Fills the tree from the pack's or a fixture's `audio_vae.*` tensors, the decoder's
    /// and the statistics; the encoder's are left out.
    public func load(weights: [String: MLXArray]) throws {
        try update(parameters: ModuleParameters.unflattened(LTX2AudioVAEWeights.sanitized(weights)), verify: .all)
    }

    /// Decodes a latent `[1, frames, melBins, channels]`, channels-last as `unpacked` hands
    /// it back, to a log-mel spectrogram `[1, outputChannels, melFrames, melBins]` in the
    /// reference's channels-first order, which is what the vocoder reads.
    public func decode(_ latent: MLXArray) -> MLXArray {
        var x = convIn(latent.asType(dtype))
        x = middle(x)
        for level in levels.reversed() { x = level(x) }
        x = convOut(silu(LTX2AudioResnetBlock.normalized(x, eps: layout.normEpsilon)))
        let frames = layout.melFrames(forLatentFrames: latent.dim(1))
        let cropped = x[0..., 0..<Swift.min(frames, x.dim(1)), 0..<Swift.min(layout.melBins, x.dim(2)), 0..<layout.outputChannels]
        return Self.padded(cropped, frames: frames, bins: layout.melBins).transposed(0, 3, 1, 2)
    }

    /// The transformer's packed tokens `[1, frames, channels * melBins]`, denormalised, as
    /// the latent the decoder reads: `[1, frames, melBins, channels]`, the packed width being
    /// channel-major (`channel * melBins + bin`), the reference's `_unpack_audio_latents`.
    public func unpacked(_ tokens: MLXArray) -> MLXArray {
        let (frames, channels, bins) = (tokens.dim(1), layout.latentChannels, layout.latentMelBins)
        return statistics.denormalised(tokens)
            .reshaped([tokens.dim(0), frames, channels, bins])
            .transposed(0, 1, 3, 2)
    }

    /// `x` padded with zeros up to `frames` by `bins`, when a decode came out short.
    private static func padded(_ x: MLXArray, frames: Int, bins: Int) -> MLXArray {
        let time = frames - x.dim(1)
        let mel = bins - x.dim(2)
        guard time > 0 || mel > 0 else { return x }
        return MLX.padded(x, widths: [0, [0, Swift.max(time, 0)], [0, Swift.max(mel, 0)], 0])
    }
}
