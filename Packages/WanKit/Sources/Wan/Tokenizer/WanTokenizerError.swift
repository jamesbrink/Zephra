import Foundation

/// What can go wrong reading the tokenizer files.
public enum WanTokenizerError: Error, Sendable {
    /// `tokenizer.json` is not there.
    case missingFile(URL)
    /// `tokenizer.json` did not hold a Unigram vocabulary with the pieces the encoder needs.
    case malformed(URL, reason: String)
}
