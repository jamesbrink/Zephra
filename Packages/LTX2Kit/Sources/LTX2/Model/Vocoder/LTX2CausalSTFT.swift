import Foundation
import MLX
import MLXNN

/// The windowed Fourier bases the mel spectrogram's convolution runs, as the checkpoint
/// stores them: `[2 * frequencies, window, 1]`, real rows then imaginary.
final class LTX2CausalSTFT: Module {
    @ParameterInfo(key: "forward_basis") var forwardBasis: MLXArray

    override init() {
        _forwardBasis.wrappedValue = MLXArray.zeros([LTX2MelSpectrogram.window + 2, LTX2MelSpectrogram.window, 1])
    }
}
