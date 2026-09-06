import Foundation
import Hub
import Tokenizers

/// Gemma 4's tokenizer, read from the `tokenizer.json` beside the text encoder's weights, with
/// the three rules LTX-2.5's encoder applies on top of it.
///
/// The prompt is stripped and encoded raw: no chat template, that is the prompt enhancer's
/// business and not the encoder's. `<bos>` is then made sure of, because Gemma 4's own
/// post-processor adds nothing and a Gemma 3 habit of trusting it would leave every prompt one
/// token short. The ids are cut to `maxLength` keeping the *front* (the tokenizer's default
/// truncation side, measured against the real checkpoint) and padded to it on the *left*.
public struct LTX2Tokenizer {
    /// Positions every prompt is padded or cut to.
    public static let maxLength = 1024

    private let tokenizer: any Tokenizer
    /// The id every prompt begins with.
    public let bosTokenID: Int
    /// The id a prompt is padded with.
    public let padTokenID: Int

    /// Loads the tokenizer from a directory holding `tokenizer.json` and `tokenizer_config.json`.
    public init(directory: URL, bosTokenID: Int = 2, padTokenID: Int = 0) throws {
        let configURL = directory.appending(path: "tokenizer_config.json")
        let dataURL = directory.appending(path: "tokenizer.json")
        for url in [configURL, dataURL]
        where !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            throw LTX2TokenizerError.missingFile(url)
        }
        do {
            tokenizer = try AutoTokenizer.from(
                tokenizerConfig: try HubApi().configuration(fileURL: configURL),
                tokenizerData: try HubApi().configuration(fileURL: dataURL))
        } catch {
            throw LTX2TokenizerError.malformed(dataURL, reason: String(describing: error))
        }
        self.bosTokenID = bosTokenID
        self.padTokenID = padTokenID
    }

    /// The ids for `prompt` the encoder reads before padding: stripped, `<bos>` first, at most
    /// `maxLength` long.
    public func encode(_ prompt: String) -> [Int] {
        var ids = tokenizer.encode(
            text: prompt.trimmingCharacters(in: .whitespacesAndNewlines), addSpecialTokens: true)
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

    /// The text for `ids`, for checking what was encoded.
    public func decode(_ ids: [Int]) -> String {
        tokenizer.decode(tokens: ids)
    }
}
