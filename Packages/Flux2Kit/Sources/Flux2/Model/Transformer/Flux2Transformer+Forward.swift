import Foundation
import MLX
import MLXNN

extension Flux2Transformer {
    /// Predicts the flow for one step.
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
    ) -> MLXArray {
        // The conditioning stays float32, and that is load-bearing rather than tidy. Every
        // modulation below is derived from it, and MLX promotes: a float32 scale times a
        // bfloat16 stream gives float32, so the activations through the blocks are float32 too.
        // That is what keeps this model clear of the broken half-precision split-K kernel in
        // mlx-swift 0.31.x; see `Flux2ParallelAttention.callAsFunction`. Casting this down to
        // match the weights would be a plausible-looking optimisation that produces NaNs on
        // M5-class hardware at some image sizes and not others.
        let conditioning = timeEmbedding(timestep.asType(.float32))

        // Computed once, here, and read by all twenty-five blocks. See `Flux2SharedModulation`.
        let imageParameters = imageModulation(conditioning)
        let textParameters = textModulation(conditioning)
        let singleParameters = singleModulation(conditioning)[0]

        var image = imageInput(latents)
        var textStream = textInput(text)

        for block in doubleBlocks {
            (image, textStream) = block(
                image: image,
                text: textStream,
                imageModulation: imageParameters,
                textModulation: textParameters,
                frequencies: frequencies)
        }

        // Text first, matching the order the rotary table was built in.
        var hidden = MLX.concatenated([textStream, image], axis: 1)
        for block in singleBlocks {
            hidden = block(hidden, modulation: singleParameters, frequencies: frequencies)
        }

        return output(outputNorm(hidden[0..., textLength...], conditioning: conditioning))
    }
}
