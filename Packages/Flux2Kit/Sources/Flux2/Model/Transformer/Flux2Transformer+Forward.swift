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
        // The sinusoid is built in float32 whatever arrives, and the result is cast to the
        // stream's dtype here, as the reference casts it. It has to be: MLX promotes, so a
        // float32 conditioning would turn every modulated activation float32 and put the
        // attention over a 4096-token image off the fused kernel. The stream's dtype is the
        // caller's choice; see `Flux2TransformerPrecision`.
        let conditioning = timeEmbedding(timestep.asType(.float32)).asType(latents.dtype)

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
