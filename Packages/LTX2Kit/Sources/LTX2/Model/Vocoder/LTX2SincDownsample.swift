import Foundation
import MLX
import MLXNN

/// The anti-aliasing activation's second half: the doubled signal halved again through the
/// checkpoint's low-pass sinc filter, the reference's `DownSample1d` at ratio two.
final class LTX2SincDownsample: Module {
    @ModuleInfo(key: "lowpass") var lowpass: LTX2SincLowpass

    static let ratio = 2
    static let taps = 12

    override init() {
        _lowpass.wrappedValue = LTX2SincLowpass()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let before = Self.taps / 2 + Self.taps % 2 - 1
        let after = Self.taps / 2
        return LTX2SincFilter.convolved(x, filter: lowpass.filter, stride: Self.ratio, before: before, after: after)
    }
}
