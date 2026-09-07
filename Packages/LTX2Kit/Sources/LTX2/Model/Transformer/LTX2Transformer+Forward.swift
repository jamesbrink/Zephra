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
    ///   - firstFrameStrength: How strongly the first latent frame is held, from 0 (not held,
    ///     which is ordinary text-to-video) to 1 (held exactly). Nil is the text-to-video path
    ///     and computes what it always did.
    ///   - textMask: An additive bias over the text tokens, or nil when every token counts.
    ///
    /// A held first frame is a **per-token noise level**, which is how the reference conditions:
    /// the video adaLN and the output head see `sigma * (1 - mask)`, so the tokens carrying the
    /// picture are told they are that much less noisy than the ones being made, while the
    /// prompt's own adaLN keeps the scalar sigma. One held frame gives that field exactly two
    /// values, so both are computed in one batch of two sigmas and chosen per token by the
    /// marker the keyframe embedding already builds.
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
        firstFrameStrength: Float? = nil,
        textMask: MLXArray? = nil
    ) throws -> MLXArray {
        let table = rotary.table(positions: layout.positions(frameRate: frameRate))
        let marker = Self.firstFrameMarker(layout)
        var x = patchify(tokens) + marker.asType(tokens.dtype) * keyframeEmbedding.asType(tokens.dtype)
        let held = firstFrameStrength.map { MLX.concatenated([sigma, sigma * (1 - $0)], axis: 0) }
        let (modulation, embedded) = timestepModulation(held ?? sigma, dtype: x.dtype)
        let (prompt, _) = promptModulation(sigma, dtype: x.dtype)
        let conditioning =
            held == nil
            ? LTX2BlockConditioning(modulation: modulation, prompt: prompt)
            : LTX2BlockConditioning(
                modulation: modulation[0..<1], prompt: prompt,
                conditioned: modulation[1..<2], marker: marker)
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
        return head(x, embedded: embedded, marker: held == nil ? nil : marker)
    }

    /// `[1, tokens, 1]`: true over the first latent frame's tokens, false elsewhere. One
    /// marker for both readers of it — the keyframe embedding, which casts it to the stream,
    /// and the per-token modulation, which selects with it.
    static func firstFrameMarker(_ layout: LTX2LatentLayout) -> MLXArray {
        let marked = layout.firstFrameTokens
        return MLX.concatenated(
            [
                MLXArray.ones([1, marked, 1], type: Bool.self),
                MLXArray.zeros([1, layout.tokens - marked, 1], type: Bool.self),
            ], axis: 1)
    }

    /// The output head: an affine-free layer norm modulated by the embedded timestep plus the
    /// model's own two-row table (shift first, then scale), then the projection to latents.
    ///
    /// With a `marker` the embedded timestep is a batch of two — the step's sigma and the held
    /// frame's, exactly two rows because one held frame is what `callAsFunction` concatenates —
    /// and the two rows are chosen per token exactly as a block's nine are. Without a `marker`
    /// `embedded` is the ordinary `[batch, 1, dim]` timestep embedding, batch meaning the
    /// request's own batch of prompts, so it is expanded and passed through whole: picking
    /// batch element 0, as the conditioned path does, would silently drop every generation past
    /// the first in a batch greater than one.
    private func head(_ x: MLXArray, embedded: MLXArray, marker: MLXArray?) -> MLXArray {
        var rows: [MLXArray]
        if let marker {
            rows = LTX2Block.rows(outputTable, Self.embedding(embedded, at: 0), as: x.dtype)
            rows = LTX2Block.blended(
                rows,
                LTX2Block.rows(outputTable, Self.embedding(embedded, at: 1), as: x.dtype),
                marker: marker)
        } else {
            rows = LTX2Block.rows(outputTable, embedded.expandedDimensions(axis: 2), as: x.dtype)
        }
        let normed = MLXFast.layerNorm(x, weight: nil, bias: nil, eps: configuration.normEps)
        return output(normed * (1 + rows[1]) + rows[0])
    }

    /// One batch element of `[batch, 1, dim]` as the `[1, 1, 1, dim]` the row table adds to.
    private static func embedding(_ embedded: MLXArray, at index: Int) -> MLXArray {
        embedded[index..<(index + 1)].expandedDimensions(axis: 2)
    }
}
