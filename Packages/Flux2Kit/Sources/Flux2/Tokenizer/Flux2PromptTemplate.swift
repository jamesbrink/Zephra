import Foundation

/// The chat wrapper FLUX.2 klein puts around a prompt before encoding it.
///
/// The reference renders Qwen3's chat template over one user message with thinking turned off,
/// and that rendering is a fixed string: no system message, and an empty think block the
/// template emits even when thinking is off. The model was trained on prompts inside exactly
/// this, so the text is part of the model rather than a formatting choice, and it is written out
/// here rather than rendered through a template engine so that what is fed to the encoder can
/// be read.
///
/// Unlike Qwen-Image, nothing is dropped afterwards. The transformer conditions on every one of
/// the padded sequence's positions, the wrapper's and the padding's included.
public enum Flux2PromptTemplate {
    /// The wrapper, with `{}` standing in for the prompt.
    public static let text = "<|im_start|>user\n{}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"

    /// Positions the encoder is always given: shorter prompts are padded up to it, longer ones
    /// cut down to it. The reference's `max_sequence_length`.
    public static let sequenceLength = 512

    /// The token every position past the prompt is filled with: `<|endoftext|>`.
    public static let padTokenID = 151_643

    /// The template with `prompt` in it.
    public static func wrapping(_ prompt: String) -> String {
        text.replacingOccurrences(of: "{}", with: prompt)
    }
}
