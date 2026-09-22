import Foundation

/// The wrapper Qwen-Image 2.1 puts around a prompt before encoding it.
///
/// The reference builds this string by hand and hands it straight to the processor rather than
/// rendering it through the chat template: the two tokenize differently and the checkpoint was
/// trained on this one. The encoder's hidden states for the system turn are then thrown away —
/// `dropIndex` of them — leaving the states from the user turn's `<|im_start|>` onwards.
///
/// `dropIndex` is a property of how this exact string tokenizes. Change a character and the
/// count changes with it, shifting every conditioning vector by a token, so the two are stated
/// together here and checked together in `TokenizerTests` against the real tokenizer.
public enum QwenImage21PromptTemplate {
    /// The system message the model was trained behind.
    public static let systemPrompt = "Comprehend and analyze the provided prompt."

    /// The text-to-image wrapper, with `{}` standing in for the prompt.
    public static let textToImage = """
        <|im_start|>system
        \(systemPrompt)<|im_end|>
        <|im_start|>user
        {}<|im_end|>
        <|im_start|>assistant

        """

    /// The wrapper for a prompt with one reference picture. More pictures are `marker(for:)`.
    public static let textAndImageToImage = """
        <|im_start|>system
        \(systemPrompt)<|im_end|>
        <|im_start|>user
        \(marker(for: 1)){}<|im_end|>
        <|im_start|>assistant

        """

    /// Leading tokens the system turn contributes, dropped before conditioning.
    ///
    /// Fourteen: `<|im_start|> system \n` then the sentence, then `<|im_end|> \n`.
    public static let dropIndex = 14

    /// Prompt tokens kept past `dropIndex`.
    ///
    /// The reference caps nothing — `model_max_length` is 262,144 — but every prompt token is
    /// about half a megabyte of prefix KV cache across the 32 blocks, paid for the whole run.
    /// 512 bounds that at 268 MB and is a very long prompt in byte-level BPE.
    public static let maxPromptTokens = 512

    /// The vision marker run for `count` reference pictures.
    ///
    /// `<image1>`, `<image2>` and so on are **ordinary text**, not special tokens: they are not
    /// in `added_tokens.json` and tokenize as their characters. Only `<|vision_start|>`,
    /// `<|image_pad|>` and `<|vision_end|>` are single tokens. There is **one** `<|image_pad|>`
    /// per picture here, not one per vision token: the processor expands it into
    /// `grid_t * grid_h * grid_w / merge²` copies from the picture's own patch grid, which is
    /// something only the tower's preprocessing knows. And the space before the second and
    /// later markers is the reference's, and it is a token.
    public static func marker(for count: Int) -> String {
        guard count > 0 else { return "" }
        var run = "<image1><|vision_start|><|image_pad|><|vision_end|>"
        guard count > 1 else { return run }
        for index in 2...count {
            run += " <image\(index)><|vision_start|><|image_pad|><|vision_end|>"
        }
        return run
    }

    /// The template for a prompt with `referenceCount` pictures in front of it.
    public static func template(referenceCount: Int) -> String {
        guard referenceCount > 0 else { return textToImage }
        return textAndImageToImage.replacingOccurrences(
            of: marker(for: 1), with: marker(for: referenceCount))
    }

    /// The template for `referenceCount` pictures with `prompt` in it.
    ///
    /// An empty prompt becomes a single space, the way the reference does it: Qwen has no
    /// beginning-of-sequence token, so an empty string leaves the encoder nothing to read.
    public static func wrapping(_ prompt: String, referenceCount: Int = 0) -> String {
        template(referenceCount: referenceCount)
            .replacingOccurrences(of: "{}", with: prompt.isEmpty ? " " : prompt)
    }
}
