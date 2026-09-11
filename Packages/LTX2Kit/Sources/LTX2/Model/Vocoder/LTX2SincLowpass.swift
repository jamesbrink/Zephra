import Foundation
import MLX
import MLXNN

/// The twelve stored taps of a low-pass sinc filter, one level down the tree from the
/// downsampler that runs them (`downsample.lowpass.filter` in the checkpoint).
final class LTX2SincLowpass: Module {
    @ParameterInfo(key: "filter") var filter: MLXArray

    override init() {
        _filter.wrappedValue = MLXArray.zeros([1, LTX2SincDownsample.taps, 1])
    }
}
