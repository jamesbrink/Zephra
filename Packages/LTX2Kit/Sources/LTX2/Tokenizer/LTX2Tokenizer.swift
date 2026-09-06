import Foundation

/// Gemma 4's tokenizer, read from the `tokenizer.json` beside the text encoder's weights, with
/// the three rules LTX-2.5's encoder applies on top of it.
///
/// The prompt is stripped and encoded raw: no chat template, that is the prompt enhancer's
/// business and not the encoder's. `<bos>` is then made sure of, because Gemma 4's own
/// post-processor adds nothing and a Gemma 3 habit of trusting it would leave every prompt one
/// token short. The ids are cut to `maxLength` keeping the *front* (the tokenizer's default
/// truncation side, measured against the real checkpoint) and padded to it on the *left*.
///
/// The encoding itself is `LTX2BytePairEncoding`, ours, with the file's added tokens matched
/// literally first so `<bos>` typed into a prompt is the token and not five characters.
public struct LTX2Tokenizer {
    /// Positions every prompt is padded or cut to.
    public static let maxLength = 1024

    private let vocabulary: LTX2TokenizerVocabulary
    /// The id every prompt begins with.
    public let bosTokenID: Int
    /// The id a prompt is padded with.
    public let padTokenID: Int

    /// Loads the tokenizer from a directory holding `tokenizer.json`.
    public init(directory: URL, bosTokenID: Int = 2, padTokenID: Int = 0) throws {
        let url = directory.appending(path: "tokenizer.json")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw LTX2TokenizerError.missingFile(url)
        }
        vocabulary = try LTX2TokenizerVocabulary(contentsOf: url)
        self.bosTokenID = bosTokenID
        self.padTokenID = padTokenID
    }

    /// The ids for `prompt` the encoder reads before padding: stripped, `<bos>` first, at most
    /// `maxLength` long.
    public func encode(_ prompt: String) -> [Int] {
        var ids = tokenize(prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        if ids.first != bosTokenID { ids.insert(bosTokenID, at: 0) }
        return Array(ids.prefix(Self.maxLength))
    }

    /// The prompt at exactly `length` positions, padded on the left, and a mask of ones over
    /// the real tokens.
    ///
    /// Left, because that is where the reference puts the padding, and the connector's register
    /// replacement and the positions the rotary embedding counts both follow from it.
    public func padded(_ prompt: String, to length: Int = LTX2Tokenizer.maxLength)
        -> (ids: [Int], mask: [Int])
    {
        let ids = Array(encode(prompt).prefix(length))
        let padding = length - ids.count
        return (
            Array(repeating: padTokenID, count: padding) + ids,
            Array(repeating: 0, count: padding) + Array(repeating: 1, count: ids.count)
        )
    }

    /// The text for `ids`, for checking what was encoded: `▁` back to a space, byte tokens back
    /// to their bytes.
    public func decode(_ ids: [Int]) -> String {
        var bytes: [UInt8] = []
        for id in ids {
            guard let token = vocabulary.tokens[id] else { continue }
            if let byte = vocabulary.byteTokens.firstIndex(of: id) {
                bytes.append(UInt8(byte))
            } else {
                bytes += token.replacingOccurrences(of: "\u{2581}", with: " ").utf8
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Added tokens first, byte-pair encoding over the stretches between them.
    private func tokenize(_ text: String) -> [Int] {
        var ids: [Int] = []
        var rest = Substring(text)
        var plain = ""
        while let scalar = rest.unicodeScalars.first {
            if let match = vocabulary.added.first(where: { rest.hasPrefix($0.text) }) {
                if !plain.isEmpty { ids += LTX2BytePairEncoding.encode(plain, with: vocabulary); plain = "" }
                ids.append(match.id)
                rest = rest.dropFirst(match.text.count)
            } else {
                plain.unicodeScalars.append(scalar)
                rest = Substring(rest.unicodeScalars.dropFirst())
            }
        }
        if !plain.isEmpty { ids += LTX2BytePairEncoding.encode(plain, with: vocabulary) }
        return ids
    }
}
