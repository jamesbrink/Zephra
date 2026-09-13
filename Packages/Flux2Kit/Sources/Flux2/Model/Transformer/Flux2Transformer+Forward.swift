import Foundation
import MLX
import MLXNN
import ZephraMLX

extension Flux2Transformer {
    /// Predicts the flow for one step.
    ///
    /// Throws only when streaming: a shard that changed under the model, or a cancellation
    /// answered between blocks.
    ///
    /// - Parameters:
    ///   - latents: Packed patch tokens, `[batch, imageTokens, inChannels]`. When editing, this
    ///     is the target's tokens followed by each reference image's.
    ///   - text: Conditioning from the encoder, `[batch, textTokens, jointAttentionDim]`.
    ///   - timestep: The noise level, from zero to one. The sinusoid scales it by 1000.
    ///   - frequencies: One rotary table over the whole `[text, image]` sequence, in that
    ///     order. Every block reads it; none of them builds one.
    ///   - textLength: How many leading positions of that sequence are text, and so are dropped
    ///     before the output projection.
    /// - Returns: The velocity, `[batch, imageTokens, outChannels]`.
    public func callAsFunction(
        latents: MLXArray,
        text: MLXArray,
        timestep: MLXArray,
        frequencies: RotaryFrequencies,
        textLength: Int
    ) throws -> MLXArray {
        // The timestep is rounded to the stream's dtype before anything reads it, and the
        // float32 sinusoid is cast back to that dtype before the MLP — the two casts the
        // reference makes, in its order, so under bfloat16 the sinusoid sees 768 for 0.77 the
        // way `diffusers` does. The trailing cast is belt and braces: MLX promotes, so a
        // float32 conditioning would turn every modulated activation float32 and put the
        // attention over a 4096-token image off the fused kernel. The stream's dtype is the
        // caller's choice; see `Flux2TransformerPrecision`.
        let conditioning = timeEmbedding(
            timestep.asType(latents.dtype), projectionDType: latents.dtype
        ).asType(latents.dtype)

        // Computed once, here, and read by all twenty-five blocks. See `Flux2SharedModulation`.
        let imageParameters = imageModulation(conditioning)
        let textParameters = textModulation(conditioning)
        let singleParameters = singleModulation(conditioning)[0]

        var image = imageInput(latents)
        var textStream = textInput(text)

        let double = { (block: Flux2DoubleBlock) in
            (image, textStream) = block(
                image: image,
                text: textStream,
                imageModulation: imageParameters,
                textModulation: textParameters,
                frequencies: frequencies)
        }
        if let doubleStream {
            // A streamed step is tens of seconds on the Mac that needs it, so a stop is
            // answered between blocks rather than at the step's end.
            try doubleStream.run { block in
                try Task.checkCancellation()
                double(block)
                return [image, textStream]
            }
        } else {
            for block in doubleBlocks { double(block) }
        }

        // Text first, matching the order the rotary table was built in.
        var hidden = MLX.concatenated([textStream, image], axis: 1)
        let single = { (block: Flux2SingleBlock) in
            hidden = block(hidden, modulation: singleParameters, frequencies: frequencies)
        }
        if let singleStream {
            try singleStream.run { block in
                try Task.checkCancellation()
                single(block)
                return [hidden]
            }
        } else {
            for block in singleBlocks { single(block) }
        }

        return output(outputNorm(hidden[0..., textLength...], conditioning: conditioning))
    }
}
