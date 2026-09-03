import Foundation
import MLX
import MLXFast
import MLXNN

/// The one attention block each tower carries, in the middle where the image is smallest.
///
/// Every position attends to every other, so this is the tower's memory high-water mark: at
/// 1024 pixels the encoder reaches it over a 128x128 grid, 16,384 positions. It is the reason
/// the decode is worth tiling.
///
/// Single-headed over the full 512 channels, because diffusers builds it with
/// `attention_head_dim` equal to the width — so the scale is one over the square root of the
/// whole width, not of a head.
final class Flux2VAEAttentionBlock: Module {
    @ModuleInfo(key: "group_norm") var norm: GroupNorm
    @ModuleInfo(key: "to_q") var queries: Linear
    @ModuleInfo(key: "to_k") var keys: Linear
    @ModuleInfo(key: "to_v") var values: Linear
    // `to_out.0` in the checkpoint: the reference wraps this projection and a dropout in a
    // `Sequential`, and dropout is nothing at inference. `Flux2VAEWeights` does the rename.
    @ModuleInfo(key: "to_out") var output: Linear

    private let channels: Int

    init(channels: Int, groups: Int) {
        self.channels = channels
        _norm.wrappedValue = .flux2(channels: channels, groups: groups)
        _queries.wrappedValue = Linear(channels, channels, bias: true)
        _keys.wrappedValue = Linear(channels, channels, bias: true)
        _values.wrappedValue = Linear(channels, channels, bias: true)
        _output.wrappedValue = Linear(channels, channels, bias: true)
    }

    /// Attends over `x`, `[batch, height, width, channels]`, and adds the result back.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let (batch, height, width) = (x.dim(0), x.dim(1), x.dim(2))
        // Row-major over the grid, which is the order the reference flattens in too.
        let flat = norm(x).reshaped([batch, height * width, channels])
        // One head, so the head axis is a bare one rather than a split of the channels.
        let attended = MLXFast.scaledDotProductAttention(
            queries: queries(flat).expandedDimensions(axis: 1),
            keys: keys(flat).expandedDimensions(axis: 1),
            values: values(flat).expandedDimensions(axis: 1),
            scale: 1 / sqrt(Float(channels)), mask: nil
        )
        .squeezed(axis: 1)

        return output(attended).reshaped([batch, height, width, channels]) + x
    }
}
