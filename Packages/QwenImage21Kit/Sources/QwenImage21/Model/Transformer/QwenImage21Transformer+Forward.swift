import Foundation
import MLX
import MLXNN
import ZephraMLX

extension QwenImage21Transformer {
    /// Predicts the flow for one step.
    ///
    /// The joint sequence is assembled here and it is the part of 2.1 a port gets wrong first.
    /// Every vision-language image slot stands for four latent tokens, so the encoder's sequence
    /// expands four-fold at those slots and the projected latents are dropped in — which puts
    /// each condition image **where the prompt put it** rather than at the front, and throws the
    /// encoder's own image embeddings away. What carries a reference picture into this model is
    /// the text the encoder wrote having looked at it. That expansion and substitution is one
    /// gather out of `[encoder ++ latents]`, which `QwenImage21JointLayout.sourceIndices` is.
    ///
    /// - Parameters:
    ///   - latents: `[batch, latentTokens, inChannels]`, every condition image first and the
    ///     target last, in `layout.shapes`' order.
    ///   - text: `[batch, encoderTokens, contextInDim]` from the vision-language encoder,
    ///     including the positions its image slots occupy.
    ///   - timestep: `[batch]`, scaled to zero-to-one; the sinusoid puts the 1000 back.
    ///   - frequencies: The rotary table over the **whole** joint sequence, whatever this step
    ///     computes.
    ///   - promptMask: The prompt's padding, or nil where nothing was padded. Batch one never
    ///     pads.
    ///   - cache: The prefix cache, with `mode` saying what to do with it.
    /// - Returns: `[batch, sequenceLength, outChannels]` on a prefill and
    ///   `[batch, targetTokens, outChannels]` on a cached step. The caller takes the target's
    ///   tokens off the end either way.
    public func callAsFunction(
        latents: MLXArray,
        text: MLXArray,
        timestep: MLXArray,
        layout: QwenImage21JointLayout,
        frequencies: RotaryFrequencies,
        promptMask: [Bool]? = nil,
        cache: QwenImage21KVCache? = nil,
        mode: QwenImage21KVCache.Mode? = nil
    ) throws -> MLXArray {
        guard cache == nil || causalCondition else {
            throw QwenImage21TransformerError.cacheRequiresCausalCondition
        }
        guard text.dim(1) == layout.encoderTokenCount else {
            throw QwenImage21TransformerError.textDoesNotMatchLayout(
                text: text.dim(1), expected: layout.encoderTokenCount)
        }

        let dtype = latents.dtype
        let decoding = mode == .cached
        let prefix = layout.prefixLength
        let sources = decoding
            ? Array(layout.sourceIndices[prefix...]) : layout.sourceIndices
        var stream = MLX.take(
            MLX.concatenated([textInput(text), imageInput(latents)], axis: 1),
            MLXArray(sources.map(Int32.init)), axis: 1)

        // `causal_condition`: an extra t = 0 row, which every text and condition token reads.
        let levels =
            causalCondition
            ? MLX.concatenated([timestep.asType(dtype), MLXArray.zeros([1], dtype: dtype)], axis: 0)
            : timestep.asType(dtype)
        let conditioning = timeEmbedding(levels, projectionDType: dtype).asType(dtype)
        let rows = causalCondition
            ? MLXArray(decoding ? Array(layout.targetTokenMask[prefix...]) : layout.targetTokenMask)
            : nil
        let parameters = QwenImage21SharedModulation.split(
            modulation(conditioning), targetTokenMask: rows)

        let rotary =
            decoding
            ? RotaryFrequencies(cos: frequencies.cos[prefix...], sin: frequencies.sin[prefix...])
            : frequencies
        let keyValid = try promptMask.map { try layout.keyValid(promptMask: $0) }
        let plan =
            decoding
            ? QwenImage21AttentionPlan.decode(
                targetTokens: layout.targetTokenCount, keyValid: keyValid)
            : QwenImage21AttentionPlan.prefill(
                segments: QwenImage21AttentionSegments(layout).segments,
                keyValid: keyValid,
                sequenceLength: layout.sequenceLength)

        var layer = 0
        let step = { (block: QwenImage21TransformerBlock) throws -> [MLXArray] in
            // A streamed step is one read of the whole transformer, so a stop is answered
            // between blocks rather than at the step's end.
            try Task.checkCancellation()
            stream = try block(
                stream,
                modulation: parameters,
                frequencies: rotary,
                plan: plan,
                cache: cache?.layers[layer],
                mode: mode,
                prefixLength: prefix)
            layer += 1
            return [stream]
        }
        if let blockStream {
            try blockStream.run(step)
        } else {
            for block in blocks { _ = try step(block) }
        }

        // The copies the first step made are graph nodes holding the whole prefill behind them
        // until something reads them; this is what makes them real.
        if mode == .extract { cache?.commit() }

        return output(
            outputNorm(stream, conditioning: conditioning, targetTokenMask: rows))
    }
}
