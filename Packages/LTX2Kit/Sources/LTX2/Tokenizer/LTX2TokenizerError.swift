import Foundation

/// What can go wrong reading the tokenizer files.
public enum LTX2TokenizerError: Error, Sendable {
    /// `tokenizer.json` is not there.
    case missingFile(URL)
    /// `tokenizer.json` did not hold a byte-pair vocabulary, its merges, or its byte tokens.
    case malformed(URL, reason: String)
}
