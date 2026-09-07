import Foundation
import MLX

/// What one timestep tells every block: the nine modulation rows and the two prompt rows, before
/// each block adds its own tables to them.
///
/// Computed once per step by the transformer's two adaLN-single heads and handed to all
/// forty-eight blocks, which is why it is a value and not something a block owns.
///
/// A run that holds a first frame carries a second set. The reference gives the video adaLN a
/// **per-token** timestep, `sigma * (1 - mask)`, which for one held frame takes exactly two
/// values: the step's sigma over the tokens being made, and `sigma * (1 - strength)` over the
/// held frame's. So the two are computed as one batch of two sigmas and told apart by `marker`
/// rather than by a `[tokens, rows, dim]` tensor nobody could afford. The prompt's adaLN keeps
/// the scalar sigma, as the reference does.
struct LTX2BlockConditioning {
    /// `[batch, 1, 9, dim]`: shift, scale and gate for the self-attention, the feed-forward and
    /// the cross-attention's queries, in that order, at the step's own sigma.
    let modulation: MLXArray
    /// `[batch, 1, 2, dim]`: shift and scale for the text the cross-attention reads.
    let prompt: MLXArray
    /// `[1, 1, 9, dim]` at the held frame's reduced sigma, or nil when nothing is held.
    let conditioned: MLXArray?
    /// `[1, tokens, 1]`, one over the held frame's tokens and zero elsewhere; nil with
    /// `conditioned`.
    let marker: MLXArray?

    init(
        modulation: MLXArray, prompt: MLXArray,
        conditioned: MLXArray? = nil, marker: MLXArray? = nil
    ) {
        self.modulation = modulation
        self.prompt = prompt
        self.conditioned = conditioned
        self.marker = marker
    }
}
