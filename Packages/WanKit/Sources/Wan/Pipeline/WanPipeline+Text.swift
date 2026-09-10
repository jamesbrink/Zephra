import Foundation
import MLX

/// From a prompt to the conditioning the transformer attends to.
extension WanPipeline {
    /// The encoder's output for `prompt`, `[1, 512, 4096]` in the stream's dtype: cleaned,
    /// tokenised, run through every UMT5 block under its padding mask, and zeroed past the end
    /// of the prompt, which is what the reference hands the transformer.
    func encodePrompt(_ prompt: String, with loaded: Loaded) throws -> MLXArray {
        let encoding = WanPromptEncoding(tokenizer: loaded.tokenizer, encoder: loaded.textEncoder)
        let embeddings = try encoding.encode(prompt)
        let context = embeddings[.newAxis, 0..., 0...].asType(loaded.activation)
        MLX.eval(context)
        return context
    }
}
