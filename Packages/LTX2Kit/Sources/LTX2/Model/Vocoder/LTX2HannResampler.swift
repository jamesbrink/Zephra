import Foundation
import MLX

/// The 16 kHz waveform brought to 48 kHz for the bandwidth extender's residual to add to: a
/// Hann-windowed sinc interpolation at ratio three, the reference's `UpSample1d` with
/// `window_type: "hann"`. The taps are not in the checkpoint; they are built here from the
/// same formula.
enum LTX2HannResampler {
    static let ratio = 3
    static let width = 7  // ceil(6 / 0.99)
    static let taps = 2 * width * ratio + 1

    /// The forty-three taps.
    static let filter: [Float] = {
        let rolloff = 0.99
        let lowpassWidth = 6.0
        return (0..<taps).map { index in
            let time = (Double(index) / Double(ratio) - Double(width)) * rolloff
            let clamped = min(max(time, -lowpassWidth), lowpassWidth)
            let window = pow(cos(clamped * Double.pi / lowpassWidth / 2), 2)
            let sinc = time == 0 ? 1 : sin(Double.pi * time) / (Double.pi * time)
            return Float(sinc * window * rolloff / Double(ratio))
        }
    }()

    /// `[batch, samples, channels]` to `[batch, 3 * samples, channels]`.
    static func resampled(_ x: MLXArray) -> MLXArray {
        LTX2SincFilter.transposed(
            x, filter: MLXArray(filter).reshaped([1, taps, 1]), ratio: ratio, pad: width,
            before: 2 * width * ratio, after: taps - ratio)
    }
}
