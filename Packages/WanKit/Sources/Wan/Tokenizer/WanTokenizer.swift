import Foundation

/// UMT5's tokenizer, read from the release's `tokenizer/tokenizer.json`, encoding the way
/// `transformers` 5.16.1's `T5Tokenizer` does for `WanPipeline`.
///
/// Added tokens are matched literally first, so `</s>` typed into a prompt is the token and
/// not four characters, as the reference has it. The stretches between them are split by
/// `WanMetaspaceSplit` and segmented by `WanUnigramEncoding`, ours, because the reference's
/// pipeline is not the file's and no library reading the file reproduces it. The ids are cut
/// to one under `maxLength`, keeping the front, and `</s>` goes last; padding is on the
/// *right* with `<pad>`, which is where the reference puts it.
///
/// One departure, deliberate: a character no piece covers becomes the file's `<unk>`, id 3,
/// where the reference hard-codes id 2, which in this vocabulary is `<s>`.
public struct WanTokenizer: Sendable {
    /// Positions every prompt is padded or cut to.
    public static let maxLength = 512

    private let vocabulary: WanTokenizerVocabulary
    /// The id every prompt ends with.
    public let eosTokenID: Int
    /// The id a prompt is padded with.
    public let padTokenID: Int
    /// The id a character the vocabulary has not got becomes.
    public var unknownTokenID: Int { vocabulary.unknownID }

    /// Loads the tokenizer from a directory holding `tokenizer.json`.
    public init(directory: URL) throws {
        let url = directory.appending(path: "tokenizer.json")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw WanTokenizerError.missingFile(url)
        }
        vocabulary = try WanTokenizerVocabulary(contentsOf: url)
        guard let eos = vocabulary.id(of: "</s>"), let pad = vocabulary.id(of: "<pad>") else {
            throw WanTokenizerError.malformed(url, reason: "no </s> or <pad> piece")
        }
        eosTokenID = eos
        padTokenID = pad
    }

    /// The ids for `text` the encoder reads before padding: at most `maxLength` long, `</s>`
    /// last.
    public func encode(_ text: String) -> [Int] {
        Array(tokenize(text).prefix(Self.maxLength - 1)) + [eosTokenID]
    }

    /// The prompt at exactly `length` positions, padded on the right, and a mask of ones over
    /// the real tokens.
    public func padded(_ text: String, to length: Int = WanTokenizer.maxLength)
        -> (ids: [Int], mask: [Int])
    {
        let ids = Array(encode(text).prefix(length))
        let padding = length - ids.count
        return (
            ids + Array(repeating: padTokenID, count: padding),
            Array(repeating: 1, count: ids.count) + Array(repeating: 0, count: padding)
        )
    }

    /// The text for `ids`, for checking what was encoded: `▁` back to a space.
    public func decode(_ ids: [Int]) -> String {
        ids.compactMap { vocabulary.tokens.indices.contains($0) ? vocabulary.tokens[$0] : nil }
            .joined()
            .replacingOccurrences(of: String(WanMetaspaceSplit.marker), with: " ")
    }

    /// Added tokens first, whitespace-split Unigram over the stretches between them.
    private func tokenize(_ text: String) -> [Int] {
        let scalars = Array(text.unicodeScalars)
        var ids: [Int] = []
        var plainStart = 0
        var index = 0
        while index < scalars.count {
            if let match = vocabulary.added.first(where: { scalars[index...].starts(with: $0.scalars) }) {
                ids += encodePlain(scalars[plainStart..<index])
                ids.append(match.id)
                index += match.scalars.count
                plainStart = index
            } else {
                index += 1
            }
        }
        return ids + encodePlain(scalars[plainStart...])
    }

    private func encodePlain(_ text: ArraySlice<Unicode.Scalar>) -> [Int] {
        WanMetaspaceSplit.pieces(of: text).flatMap { WanUnigramEncoding.encode($0, with: vocabulary) }
    }
}
