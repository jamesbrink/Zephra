import Foundation
import MLX
import MLXFast
import MLXNN

extension LTX2Transformer {
    /// Predicts the velocity for one step.
    ///
    /// - Parameters:
    ///   - tokens: The noisy latent as tokens, `[batch, tokens, inChannels]`, in `layout`'s order.
    ///   - text: The connector's output, `[batch, textTokens, crossAttentionDim]`.
    ///   - sigma: The noise level, `[batch]`, from zero to one; the embedding scales it.
    ///   - layout: The latent's shape, for the rotary positions and the first-frame marker.
    ///   - frameRate: Frames per second of the clip being made; time positions are seconds.
    ///   - textMask: An additive bias over the text tokens, or nil when every token counts.
    ///
    /// The stream runs in the tokens' dtype; the text and the conditioning are cast to it. A
    /// resident run evaluates the stream every `blocksPerEval` blocks; a streamed one is
    /// evaluated block by block by the stream itself, which is also where a stop is answered.
    /// Throws only when streaming: a shard that changed under the model, or a cancellation.
    public func callAsFunction(
        tokens: MLXArray,
        text: MLXArray,
        sigma: MLXArray,
        layout: LTX2LatentLayout,
        frameRate: Double,
        textMask: MLXArray? = nil
    ) throws -> MLXArray {
        let table = rotary.table(positions: layout.positions(frameRate: frameRate))
        var x = patchify(tokens) + firstFrameMarker(layout, dtype: tokens.dtype) * keyframeEmbedding.asType(tokens.dtype)
        let (modulation, embedded) = timestepModulation(sigma, dtype: x.dtype)
        let (prompt, _) = promptModulation(sigma, dtype: x.dtype)
        let conditioning = LTX2BlockConditioning(modulation: modulation, prompt: prompt)
        let context = text.asType(x.dtype)

        if let stream {
            try stream.run { block in
                try Task.checkCancellation()
                x = block(x, text: context, conditioning: conditioning, rotary: table, textMask: textMask)
                return [x]
            }
        } else {
            for (index, block) in blocks.enumerated() {
                x = block(x, text: context, conditioning: conditioning, rotary: table, textMask: textMask)
                if (index + 1) % blocksPerEval == 0 { MLX.eval(x) }
            }
        }
        return head(x, embedded: embedded)
    }

    /// `[1, tokens, 1]`: one over the first latent frame's tokens, zero elsewhere.
    private func firstFrameMarker(_ layout: LTX2LatentLayout, dtype: DType) -> MLXArray {
        let marked = layout.firstFrameTokens
        return MLX.concatenated(
            [MLXArray.ones([1, marked, 1]), MLXArray.zeros([1, layout.tokens - marked, 1])], axis: 1
        ).asType(dtype)
    }

    /// The output head: an affine-free layer norm modulated by the embedded timestep plus the
    /// model's own two-row table (shift first, then scale), then the projection to latents.
    private func head(_ x: MLXArray, embedded: MLXArray) -> MLXArray {
        let rows = LTX2Block.rows(outputTable, embedded.expandedDimensions(axis: 2), as: x.dtype)
        let normed = MLXFast.layerNorm(x, weight: nil, bias: nil, eps: configuration.normEps)
        return output(normed * (1 + rows[1]) + rows[0])
    }
}
