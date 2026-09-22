import Foundation
import MLX

extension QwenImage21PromptEncoder {
    /// The conditioning for `prompt` wrapped in the template for however many `references`
    /// there are.
    ///
    /// The prompt is capped at `QwenImage21PromptTemplate.maxPromptTokens`, which the reference
    /// does not do — it has no cap at all, and `model_max_length` is 262,144 — because every
    /// prompt token is about half a megabyte of prefix key-value cache across the 32 blocks,
    /// paid for the whole run. `PROVENANCE.md` states it.
    public func encode(
        _ prompt: String, tokenizer: QwenImage21Tokenizer, references: [MLXArray] = []
    ) throws -> QwenImage21PromptEncoding {
        try encode(
            ids: tokenizer.encode(
                prompt, limit: QwenImage21PromptTemplate.maxPromptTokens,
                referenceCount: references.count),
            references: references)
    }
}
