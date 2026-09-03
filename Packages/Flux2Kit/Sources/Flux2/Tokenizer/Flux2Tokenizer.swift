import Foundation
import Hub
import Tokenizers

/// Qwen3's byte-level BPE, read from the `tokenizer.json` the snapshot ships.
///
/// klein publishes the fast tokenizer file, so unlike Qwen-Image there is nothing to assemble:
/// `AutoTokenizer` reads the two JSON files as they are.
public struct Flux2Tokenizer {
    private let tokenizer: any Tokenizer

    /// Loads the tokenizer from a snapshot's `tokenizer` directory.
    public init(snapshot: URL) throws {
        let directory = snapshot.appending(path: "tokenizer")
        let configURL = directory.appending(path: "tokenizer_config.json")
        let dataURL = directory.appending(path: "tokenizer.json")
        for url in [configURL, dataURL]
        where !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            throw Flux2TokenizerError.missingFile(url)
        }
        do {
            tokenizer = try AutoTokenizer.from(
                tokenizerConfig: try HubApi().configuration(fileURL: configURL),
                tokenizerData: try HubApi().configuration(fileURL: dataURL)
            )
        } catch {
            throw Flux2TokenizerError.malformed(dataURL)
        }
    }

    /// The token ids for `text`, with no template applied.
    public func encode(_ text: String) -> [Int] {
        tokenizer.encode(text: text)
    }

    /// The token ids for a prompt inside klein's chat wrapper.
    public func encode(prompt: String) -> [Int] {
        encode(Flux2PromptTemplate.wrapping(prompt))
    }

    /// The wrapped prompt at exactly `length` positions, cut or padded on the right, and how
    /// many of those positions are the prompt rather than padding.
    ///
    /// Padding is on the right and the count is returned beside the ids because the encoder's
    /// mask needs it: a padded position must still see the whole prompt before it, and every
    /// position after it must not see it.
    public func padded(prompt: String, to length: Int) -> (ids: [Int], validCount: Int) {
        let ids = Array(encode(prompt: prompt).prefix(length))
        let padding = Array(repeating: Flux2PromptTemplate.padTokenID, count: length - ids.count)
        return (ids + padding, ids.count)
    }

    /// The text for `ids`, for checking what was encoded.
    public func decode(_ ids: [Int]) -> String {
        tokenizer.decode(tokens: ids)
    }
}
