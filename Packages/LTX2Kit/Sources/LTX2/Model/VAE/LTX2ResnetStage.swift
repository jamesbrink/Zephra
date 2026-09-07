import Foundation
import MLX
import MLXNN

/// A run of residual blocks at one width: one of the decoder's `up_blocks.N.res_blocks` or the
/// encoder's `down_blocks.N.res_blocks`.
///
/// The official layout interleaves these with the resamplers in one list, which is why a stage
/// is a module of its own with the blocks under `res_blocks` rather than a loop in the decoder:
/// the checkpoint's key for block `M` of stage `N` is `up_blocks.N.res_blocks.M`.
final class LTX2ResnetStage: Module {
    @ModuleInfo(key: "res_blocks") var blocks: [LTX2ResnetBlock3D]

    init(channels: Int, blocks: Int, causal: Bool = false) {
        _blocks.wrappedValue = (0..<blocks).map { _ in
            LTX2ResnetBlock3D(channels: channels, causal: causal)
        }
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        blocks.reduce(x) { $1($0) }
    }
}
