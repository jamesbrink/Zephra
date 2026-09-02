import Foundation

/// The wrapper Qwen-Image puts around a prompt before encoding it.
///
/// The model was trained on prompts inside this exact system message, so the text is part of the
/// model, not a formatting choice. The encoder's hidden states for the wrapper are then thrown
/// away — `dropIndex` of them — leaving only the states for the prompt itself.
///
/// `dropIndex` is a property of how this exact string tokenises. Change a character of the
/// template and the count changes with it, shifting every conditioning vector by a token, so the
/// two are stated together and checked together.
public enum QwenImagePromptTemplate {
    /// The system message, with `{}` standing in for the prompt.
    public static let text = """
        <|im_start|>system
        Describe the image by detailing the color, shape, size, texture, quantity, text, spatial \
        relationships of the objects and background:<|im_end|>
        <|im_start|>user
        {}<|im_end|>
        <|im_start|>assistant

        """

    /// Leading tokens the template contributes, dropped before conditioning.
    public static let dropIndex = 34

    /// The template with `prompt` in it.
    public static func wrapping(_ prompt: String) -> String {
        text.replacingOccurrences(of: "{}", with: prompt)
    }
}
