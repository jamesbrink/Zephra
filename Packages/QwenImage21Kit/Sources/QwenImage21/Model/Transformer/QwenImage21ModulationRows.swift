import Foundation
import MLX

/// Which row of the modulation table each token reads.
///
/// Under `causal_condition` the timestep is a batch of sampled levels with a **`t = 0` row
/// appended**, so the table has `batch + 1` rows. Target-image tokens take their own sample's
/// row; every text and condition-image token takes the `t = 0` row. That is the whole of what
/// makes the prefix independent of the denoising step, and therefore what makes the prefix KV
/// cache correct rather than an approximation.
///
/// A nil mask is the model without `causal_condition`, and then every token shares its sample's
/// row — one vector broadcast across the sequence rather than a tensor the sequence's own size.
enum QwenImage21ModulationRows {
    /// Broadcasts `params`, `[rows, dim]`, over the token axis.
    ///
    /// - Returns: `[batch, 1, dim]` for a nil mask, otherwise `[batch, tokens, dim]`, where
    ///   `batch` is `rows - 1`.
    static func select(_ params: MLXArray, targetTokenMask: MLXArray?) -> MLXArray {
        guard let targetTokenMask else { return params.expandedDimensions(axis: 1) }
        let rows = params.dim(0)
        let real = params[..<(rows - 1)].expandedDimensions(axis: 1)
        let zero = params[(rows - 1)...].expandedDimensions(axis: 0)
        return MLX.which(targetTokenMask.reshaped([1, -1, 1]), real, zero)
    }
}
