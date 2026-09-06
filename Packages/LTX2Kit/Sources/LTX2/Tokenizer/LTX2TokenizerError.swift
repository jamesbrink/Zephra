import Foundation

/// What can go wrong reading the tokenizer files.
public enum LTX2TokenizerError: Error, Sendable {
    /// One of the two JSON files is not there.
    case missingFile(URL)
    /// `tokenizer.json` did not parse into a tokenizer.
    case malformed(URL, reason: String)
}
