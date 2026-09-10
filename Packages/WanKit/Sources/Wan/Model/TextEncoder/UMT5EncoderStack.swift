import Foundation
import MLX
import MLXNN

/// The `encoder.` subtree of the checkpoint: the blocks and the final norm.
///
/// The token table is not here. The release stores it once as `shared.weight` at the root,
/// and the reference's `encoder.embed_tokens` is a tied view of that tensor which the
/// checkpoint does not carry; `UMT5TextEncoder` owns the table and runs the blocks, since the
/// stream that reads them from disk is attached there.
final class UMT5EncoderStack: Module {
    @ModuleInfo(key: "block") var block: [UMT5Block]
    @ModuleInfo(key: "final_layer_norm") var finalLayerNorm: RMSNorm

    init(_ configuration: UMT5Configuration) {
        _block.wrappedValue = (0..<configuration.numLayers).map { _ in UMT5Block(configuration) }
        _finalLayerNorm.wrappedValue = RMSNorm(
            dimensions: configuration.dModel, eps: configuration.layerNormEpsilon)
    }
}
