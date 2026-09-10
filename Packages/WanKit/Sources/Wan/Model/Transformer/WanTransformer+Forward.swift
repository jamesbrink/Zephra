import Foundation
import MLX
import MLXNN

extension WanTransformer {
    /// Predicts the velocity for one step.
    ///
    /// - Parameters:
    ///   - latent: The noisy latent, `[batch, channels, frames, height, width]`, as the
    ///     reference takes it; it is channels-last only inside the patch embedding.
    ///   - text: The text encoder's embeddings, `[batch, textTokens, textDim]`.
    ///   - timesteps: One timestep per token, `[batch, tokens]`, in the model's 0 to 1000
    ///     units, or `[batch]` for one timestep over every token of a batch element. An
    ///     image-to-video run gives the first latent frame's tokens 0 and the rest the step's,
    ///     which is how the reference's pipeline conditions on a held frame.
    ///
    /// The stream runs in the latent's dtype; the text and the conditioning are cast to it. A
    /// resident run evaluates every `blocksPerEval` blocks; a streamed one is evaluated block
    /// by block by the stream itself, which is also where a stop is answered. Throws only when
    /// streaming: a shard that changed under the model, or a cancellation.
    ///
    /// - Returns: The velocity in the latent's shape.
    public func callAsFunction(latent: MLXArray, text: MLXArray, timesteps: MLXArray) throws -> MLXArray {
        let grid = patchEmbedding.grid(of: latent)
        let table = rotaryTable(frames: grid.frames, height: grid.height, width: grid.width)
        var x = patchEmbedding.tokens(of: latent)
        let field = WanTimestepField(timesteps)
        let (embedded, modulation, context) = conditionEmbedder(field.values, text: text, dtype: x.dtype)

        if let stream {
            try stream.run { block in
                try Task.checkCancellation()
                x = block(x, text: context, modulation: field.perToken(modulation), rotary: table)
                return [x]
            }
        } else {
            for (index, block) in blocks.enumerated() {
                x = block(x, text: context, modulation: field.perToken(modulation), rotary: table)
                if (index + 1) % blocksPerEval == 0 { MLX.eval(x) }
            }
        }
        return unpatchify(head(x, embedded: field.perToken(embedded)), grid: grid)
    }

    /// The output head: an affine-free layer norm modulated per token by the embedded
    /// timestep plus the model's own two-row table (shift first, then scale), then the
    /// projection to the patch's latent values.
    private func head(_ x: MLXArray, embedded: MLXArray) -> MLXArray {
        let rows = WanTransformerBlock.rows(outputTable, embedded.expandedDimensions(axis: 2))
        let normed = WanLayerNorm.normalize(x, eps: configuration.eps)
        return output((normed * (1 + rows[1]) + rows[0]).asType(x.dtype))
    }

    /// `[batch, tokens, channels * patch]` back into `[batch, channels, frames, height, width]`,
    /// each token's values laid out over its patch's cells as the reference's permute lays
    /// them.
    private func unpatchify(_ x: MLXArray, grid: (frames: Int, height: Int, width: Int)) -> MLXArray {
        let patch = configuration.patchSize
        let cells = x.reshaped([x.shape[0], grid.frames, grid.height, grid.width, patch[0], patch[1], patch[2], -1])
        return cells.transposed(0, 7, 1, 4, 2, 5, 3, 6).reshaped([
            x.shape[0], -1, grid.frames * patch[0], grid.height * patch[1], grid.width * patch[2],
        ])
    }
}
