import Foundation
import MLX
import MLXNN

/// The shift, scale, and gate every block of one kind modulates by.
///
/// The striking thing about FLUX.2 is that this is **shared**. One projection is computed once
/// per forward pass and its numbers are handed to all five dual-stream blocks, or to all twenty
/// single-stream blocks. That is why the checkpoint carries three modulation tensors in total —
/// `double_stream_modulation_img`, `double_stream_modulation_txt`, `single_stream_modulation` —
/// rather than one per block the way Qwen-Image does. Giving each block its own would load
/// cleanly from a checkpoint that has none to give, and then modulate by whatever the
/// initialiser left behind.
///
/// A dual-stream block needs two sets, one for its attention half and one for its feed-forward
/// half; a single-stream block runs both halves in parallel off one set.
///
/// The chunk order is `shift, scale, gate` and modulation is `x * (1 + scale) + shift`. The
/// final norm chunks the other way round; see `Flux2AdaLayerNormContinuous`.
final class Flux2SharedModulation: Module {
    /// Shift, scale, and gate for one half of a block.
    struct Parameters {
        let shift: MLXArray
        let scale: MLXArray
        let gate: MLXArray

        /// Applies the shift and scale, leaving the gate for the residual.
        func modulate(_ x: MLXArray) -> MLXArray {
            x * (1 + scale) + shift
        }
    }

    @ModuleInfo(key: "linear") var projection: Linear

    private let sets: Int

    /// - Parameters:
    ///   - dim: The model's width.
    ///   - sets: How many shift/scale/gate triples this projection produces.
    init(dim: Int, sets: Int) {
        self.sets = sets
        _projection.wrappedValue = Linear(dim, 3 * sets * dim, bias: false)
    }

    /// One `Parameters` per set, in the order the reference chunks them.
    func callAsFunction(_ conditioning: MLXArray) -> [Parameters] {
        Self.split(projection(silu(conditioning)), sets: sets)
    }

    /// Chunks a projected `[batch, 3 * sets * dim]` tensor into its sets.
    ///
    /// Separate from the projection because the reference keeps them separate too: the model
    /// projects once and the blocks split, so a block never sees the projection. Each chunk
    /// gains a token axis and broadcasts across the sequence, the conditioning being one vector
    /// for the whole image.
    static func split(_ all: MLXArray, sets: Int) -> [Parameters] {
        let width = all.shape[all.ndim - 1] / (3 * sets)
        func chunk(_ index: Int) -> MLXArray {
            all[.ellipsis, (index * width)..<((index + 1) * width)].expandedDimensions(axis: 1)
        }
        return (0..<sets).map { set in
            Parameters(shift: chunk(3 * set), scale: chunk(3 * set + 1), gate: chunk(3 * set + 2))
        }
    }
}
