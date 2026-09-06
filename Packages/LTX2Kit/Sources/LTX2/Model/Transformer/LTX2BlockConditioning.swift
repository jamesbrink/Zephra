import Foundation
import MLX

/// What one timestep tells every block: the nine modulation rows and the two prompt rows, before
/// each block adds its own tables to them.
///
/// Computed once per step by the transformer's two adaLN-single heads and handed to all
/// forty-eight blocks, which is why it is a value and not something a block owns.
struct LTX2BlockConditioning {
    /// `[batch, 1, 9, dim]`: shift, scale and gate for the self-attention, the feed-forward and
    /// the cross-attention's queries, in that order.
    let modulation: MLXArray
    /// `[batch, 1, 2, dim]`: shift and scale for the text the cross-attention reads.
    let prompt: MLXArray
}
