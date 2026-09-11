import Foundation
import MLX
import MLXNN

/// LTX-2.5's vocoder with bandwidth extension: the audio decoder's log-mel spectrogram to a
/// stereo waveform at 48 kHz.
///
/// The first generator makes a 16 kHz waveform; a causal log-mel of that waveform feeds the
/// second, whose output is the high band the first could not make; the two are added, the
/// first resampled to 48 kHz through a Hann sinc, and clamped to -1...1. Computes in whatever
/// dtype its weights hold; the loader casts them to float32, since bfloat16 accumulated over
/// a hundred convolutions loses the spectrum (the MIT MLX port measured it).
public final class LTX2Vocoder: Module {
    @ModuleInfo(key: "vocoder") var generator: LTX2VocoderGenerator
    @ModuleInfo(key: "bwe_generator") var extender: LTX2VocoderGenerator
    @ModuleInfo(key: "mel_stft") var spectrogram: LTX2MelSpectrogram

    /// Samples a second the waveform comes out at.
    public static let outputSampleRate = 48_000
    /// Samples a second the first generator makes.
    static let inputSampleRate = 16_000

    /// The real vocoder by default; a doll's-house fixture names narrower generators.
    public init(
        generator: LTX2VocoderGeneratorLayout = .ltx25Vocoder,
        extender: LTX2VocoderGeneratorLayout = .ltx25BandwidthExtender
    ) {
        _generator.wrappedValue = LTX2VocoderGenerator(generator)
        _extender.wrappedValue = LTX2VocoderGenerator(extender)
        _spectrogram.wrappedValue = LTX2MelSpectrogram()
    }

    /// The dtype the vocoder computes in: the one its weights hold.
    public var dtype: DType { generator.convIn.weight.dtype }

    /// Fills the tree from the pack's or a fixture's `vocoder.*` tensors.
    public func load(weights: [String: MLXArray]) throws {
        try update(parameters: ModuleParameters.unflattened(LTX2VocoderWeights.sanitized(weights)), verify: .all)
    }

    /// A log-mel `[1, channels, frames, bins]`, as the audio decoder hands it back, to a
    /// waveform `[1, channels, samples]` at 48 kHz.
    public func callAsFunction(_ mel: MLXArray) -> MLXArray {
        let batch = mel.dim(0)
        let channels = mel.dim(1)
        // The generator reads every channel's bins together: `[batch, frames, channels * bins]`,
        // channel-major, the reference's transpose and flatten.
        let stacked = mel.asType(dtype).transposed(0, 2, 1, 3).reshaped([batch, mel.dim(2), -1])
        var low = generator(stacked)  // [batch, samples16, channels]
        let samples = low.dim(1)
        let remainder = samples % LTX2MelSpectrogram.hop
        if remainder != 0 {
            low = MLX.padded(low, widths: [0, [0, LTX2MelSpectrogram.hop - remainder], 0])
        }
        // Each channel's own spectrogram, then the two side by side for the extender.
        let flat = low.transposed(0, 2, 1).reshaped([batch * channels, -1])
        let logMel = spectrogram(flat)  // [batch * channels, frames, bins]
        let frames = logMel.dim(1)
        let perChannel = logMel.reshaped([batch, channels, frames, -1]).transposed(0, 2, 1, 3)
        let residual = extender(perChannel.reshaped([batch, frames, -1]))
        let skip = LTX2HannResampler.resampled(low)
        let wide = Swift.min(residual.dim(1), skip.dim(1))
        let sum = residual[0..., 0..<wide, 0...] + skip[0..., 0..<wide, 0...]
        let kept = samples * Self.outputSampleRate / Self.inputSampleRate
        return MLX.clip(sum, min: -1, max: 1)[0..., 0..<Swift.min(kept, wide), 0...].transposed(0, 2, 1)
    }
}
