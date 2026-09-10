import Foundation
import MLX

/// From a prompt to the conditioning the transformer attends to, as `WanPipeline`'s
/// `_get_t5_prompt_embeds` does it.
///
/// The prompt is cleaned, tokenised to `maxLength` with `</s>` and right padding, and run
/// through the encoder under its padding mask; then every position past the prompt's own
/// tokens is zeroed. The encoder computes those positions (they attend to the real tokens),
/// but the reference throws them away and pads with zeros, so the transformer sees zeros
/// there and no mask. The result is always `[maxLength, dModel]`, whatever the prompt.
public struct WanPromptEncoding {
    /// Positions every prompt is padded or cut to, the pipeline's `max_sequence_length`.
    public static let maxLength = WanTokenizer.maxLength

    private let tokenizer: WanTokenizer
    private let encoder: UMT5TextEncoder

    init(tokenizer: WanTokenizer, encoder: UMT5TextEncoder) {
        self.tokenizer = tokenizer
        self.encoder = encoder
    }

    /// The encoder's last hidden state over `prompt`, `[maxLength, dModel]` in the encoder's
    /// dtype, zero past the prompt's `</s>`.
    public func encode(_ prompt: String, maxLength: Int = WanPromptEncoding.maxLength) throws -> MLXArray {
        let (ids, mask) = tokenizer.padded(WanPromptCleaning.clean(prompt), to: maxLength)
        let tokens = MLXArray(ids.map(Int32.init))[.newAxis, 0...]
        let padding = MLXArray(mask.map(Int32.init))[.newAxis, 0...]
        let hidden = try encoder.lastHiddenState(tokens, padding: padding)[0]
        let kept = padding[0][0..., .newAxis] .> 0
        let embeddings = MLX.where(kept, hidden, MLXArray(Float(0)).asType(hidden.dtype))
        MLX.eval(embeddings)
        return embeddings
    }
}
