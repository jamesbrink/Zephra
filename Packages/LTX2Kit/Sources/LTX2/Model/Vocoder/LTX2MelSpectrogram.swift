import Foundation
import MLX
import MLXNN

/// A causal log-mel spectrogram of a waveform, the bandwidth extender's input: a
/// short-time Fourier transform as a strided convolution with the checkpoint's own
/// windowed bases, its magnitude through the checkpoint's mel filterbank, and a log.
///
/// The window is 512 samples at a hop of 80, padded 432 samples before and none after so
/// every frame reads only what came before it (the reference's `CausalSTFT`). The inverse
/// basis the checkpoint also ships is never read and the build leaves it out.
final class LTX2MelSpectrogram: Module {
    @ParameterInfo(key: "mel_basis") var melBasis: MLXArray
    @ModuleInfo(key: "stft_fn") var transform: LTX2CausalSTFT

    static let window = 512
    static let hop = 80
    static let bins = 64

    override init() {
        _melBasis.wrappedValue = MLXArray.zeros([Self.bins, Self.window / 2 + 1])
        _transform.wrappedValue = LTX2CausalSTFT()
    }

    /// `[batch, samples]` to `[batch, frames, bins]`, `frames` being `samples / hop` once the
    /// caller has padded the waveform to a whole number of hops.
    func callAsFunction(_ waveform: MLXArray) -> MLXArray {
        let padded = MLX.padded(waveform[0..., 0..., .newAxis], widths: [0, [Self.window - Self.hop, 0], 0])
        let spectrum = MLX.conv1d(padded, transform.forwardBasis.asType(waveform.dtype), stride: Self.hop)
        let frequencies = Self.window / 2 + 1
        let real = spectrum[0..., 0..., 0..<frequencies]
        let imaginary = spectrum[0..., 0..., frequencies...]
        let magnitude = MLX.sqrt(real * real + imaginary * imaginary)
        let mel = MLX.matmul(magnitude, melBasis.asType(waveform.dtype).transposed())
        return MLX.log(MLX.maximum(mel, 1e-5))
    }
}
