import Foundation
import Hub
import Tokenizers

/// Qwen2's byte-level BPE, read from the `tokenizer.json` the snapshot ships.
///
/// 2.1 publishes the fast tokenizer file under `processor/`, so unlike Qwen-Image 2512 there is
/// nothing to assemble: `AutoTokenizer` reads the two JSON files as they are. The kind is
/// byte-for-byte Qwen2.5-VL's — an NFC normalizer, a `Split` on Qwen2's own pre-tokenization
/// regex, then a `ByteLevel` step that maps bytes without splitting again — which is what makes
/// the ids match; `TokenizerTests` pins twenty-five prompts against the reference's own.
///
/// The `processor/` directory is shipped whole on purpose. The chat template is never used at
/// inference, since `QwenImage21PromptTemplate` builds the string by hand, but `dropIndex` is
/// derived from it and the suite that checks the constant needs the template to derive it from.
public struct QwenImage21Tokenizer {
    private let tokenizer: any Tokenizer

    /// Loads the tokenizer from a snapshot's `processor` directory.
    public init(snapshot: URL) throws {
        let directory = snapshot.appending(path: "processor")
        let configURL = directory.appending(path: "tokenizer_config.json")
        let dataURL = directory.appending(path: "tokenizer.json")
        for url in [configURL, dataURL]
        where !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            throw QwenImage21TokenizerError.missingFile(url)
        }
        do {
            tokenizer = try AutoTokenizer.from(
                tokenizerConfig: try HubApi().configuration(fileURL: configURL),
                tokenizerData: try HubApi().configuration(fileURL: dataURL)
            )
        } catch {
            throw QwenImage21TokenizerError.malformed(dataURL, reason: String(describing: error))
        }
    }

    /// The token ids for `text`, with no template around it.
    public func encode(_ text: String) -> [Int] {
        tokenizer.encode(text: text)
    }

    /// The token ids for a prompt inside the template for `referenceCount` pictures.
    public func encode(prompt: String, referenceCount: Int = 0) -> [Int] {
        encode(QwenImage21PromptTemplate.wrapping(prompt, referenceCount: referenceCount))
    }

    /// The same, keeping at most `limit` tokens of the prompt after the system turn.
    ///
    /// The cap is on the prompt, so the kept length is `dropIndex + limit`: the system turn's
    /// fourteen tokens are dropped before conditioning and would otherwise eat into the budget.
    /// Truncation keeps the **front**, which is where somebody says what they want; the
    /// encoder is causal, so cutting the tokens here gives exactly the states the reference
    /// would have given for what is kept, and skips the work for what is not.
    ///
    /// A prompt long enough to be cut loses the template's own tail as well. That tail is
    /// `<|im_end|>\n<|im_start|>assistant\n`, five tokens of scaffolding at the end of five
    /// hundred of prompt, and the alternative — splicing the tail back on after a cut — would
    /// make the ids for a long prompt something the reference never produces for any input.
    public func encode(_ prompt: String, limit: Int, referenceCount: Int = 0) -> [Int] {
        let ids = encode(prompt: prompt, referenceCount: referenceCount)
        return Array(ids.prefix(QwenImage21PromptTemplate.dropIndex + limit))
    }

    /// The text for `ids`, for checking what was encoded.
    public func decode(_ ids: [Int]) -> String {
        tokenizer.decode(tokens: ids)
    }

    /// How many tokens the system turn costs this tokenizer, which is what `dropIndex` has to
    /// equal. Derived rather than assumed, so a processor that moved is caught by a test
    /// rather than by a picture of the wrong prompt.
    public var systemTurnTokenCount: Int {
        let whole = encode(QwenImage21PromptTemplate.textToImage.replacingOccurrences(of: "{}", with: ""))
        let userTurn = encode("<|im_start|>user\n")
        guard let start = Self.index(of: userTurn, in: whole) else { return whole.count }
        return start
    }

    /// Where `needle` first begins inside `haystack`, or nil.
    private static func index(of needle: [Int], in haystack: [Int]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return start
        }
        return nil
    }
}
