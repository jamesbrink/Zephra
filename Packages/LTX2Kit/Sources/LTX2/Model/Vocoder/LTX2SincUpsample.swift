import Foundation
import MLX
import MLXNN

/// The anti-aliasing activation's first half: the signal doubled through a Kaiser-windowed
/// sinc filter stored in the checkpoint, the reference's `UpSample1d` at ratio two.
final class LTX2SincUpsample: Module {
    @ParameterInfo(key: "filter") var filter: MLXArray

    static let ratio = 2
    static let taps = 12

    override init() {
        _filter.wrappedValue = MLXArray.zeros([1, Self.taps, 1])
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        // The reference's arithmetic for a twelve-tap filter at ratio two: five samples of
        // edge padding, then fifteen trimmed off either end of the transposed convolution.
        let pad = Self.taps / Self.ratio - 1
        let before = pad * Self.ratio + (Self.taps - Self.ratio) / 2
        let after = pad * Self.ratio + (Self.taps - Self.ratio + 1) / 2
        return LTX2SincFilter.transposed(x, filter: filter, ratio: Self.ratio, pad: pad, before: before, after: after)
    }
}
