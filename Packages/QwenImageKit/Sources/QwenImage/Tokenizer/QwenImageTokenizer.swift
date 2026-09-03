import Foundation
import Hub
import Tokenizers

/// Qwen's byte-level BPE, assembled from the files the snapshot actually ships.
///
/// Qwen-Image publishes `vocab.json` and `merges.txt` but no `tokenizer.json`, so the fast path
/// through `AutoTokenizer` has nothing to read and the vocabulary and merge list have to be
/// assembled into the configuration it expects. The assembly below follows the one in
/// `Packages/ZImageKit` (MIT, mzbac/zimage.swift), which solved the same problem for the same
/// tokenizer family.
///
/// Qwen-Image does not apply a chat template. It formats one literal system message around the
/// prompt; see `QwenImagePromptTemplate`.
public struct QwenImageTokenizer {
    private let tokenizer: any Tokenizer

    /// Loads the tokenizer from a snapshot's `tokenizer` directory.
    public init(snapshot: URL) throws {
        let directory = snapshot.appending(path: "tokenizer")
        let configURL = directory.appending(path: "tokenizer_config.json")
        guard FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            throw QwenImageTokenizerError.missingFile(configURL)
        }
        tokenizer = try AutoTokenizer.from(
            tokenizerConfig: try HubApi().configuration(fileURL: configURL),
            tokenizerData: try Self.bpe(in: directory)
        )
    }

    /// The token ids for `text`, with no template applied.
    public func encode(_ text: String) -> [Int] {
        tokenizer.encode(text: text)
    }

    /// The token ids for a prompt inside Qwen-Image's own system message.
    public func encode(prompt: String) -> [Int] {
        encode(QwenImagePromptTemplate.wrapping(prompt))
    }

    /// The same, keeping at most `limit` tokens of the prompt after the template's prefix.
    ///
    /// The reference encodes the whole wrapped prompt and then keeps the first `limit` hidden
    /// states after the prefix. The encoder is causal, so cutting the tokens here gives the same
    /// states for what is kept and skips the work for what is not.
    public func encode(prompt: String, limit: Int) -> [Int] {
        Array(encode(prompt: prompt).prefix(QwenImagePromptTemplate.dropIndex + limit))
    }

    /// Builds the tokenizer data `AutoTokenizer` would have read from `tokenizer.json`.
    private static func bpe(in directory: URL) throws -> Config {
        let vocabURL = directory.appending(path: "vocab.json")
        let mergesURL = directory.appending(path: "merges.txt")
        guard let vocabData = try? Data(contentsOf: vocabURL) else {
            throw QwenImageTokenizerError.missingFile(vocabURL)
        }
        guard
            let vocabObject = try? JSONSerialization.jsonObject(with: vocabData)
                as? [String: Any]
        else {
            throw QwenImageTokenizerError.malformed(vocabURL)
        }
        var vocabulary = vocabObject.compactMapValues { $0 as? Int }

        // Added tokens are not in vocab.json but do have ids, and the template's markers are
        // among them, so a missing one shifts every prompt.
        var added: [[String: Any]] = []
        let addedURL = directory.appending(path: "added_tokens.json")
        if let addedData = try? Data(contentsOf: addedURL),
            let addedObject = try? JSONSerialization.jsonObject(with: addedData)
                as? [String: Any]
        {
            for (token, id) in addedObject.compactMapValues({ $0 as? Int }) {
                vocabulary[token] = id
                added.append([
                    "id": id, "content": token,
                    "lstrip": false, "rstrip": false, "special": true,
                ])
            }
        }

        guard let mergesText = try? String(contentsOf: mergesURL, encoding: .utf8) else {
            throw QwenImageTokenizerError.missingFile(mergesURL)
        }
        let merges =
            mergesText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        var data: [String: Any] = [
            "model": ["vocab": vocabulary, "merges": merges],
            "preTokenizer": [
                "type": "ByteLevel", "addPrefixSpace": false,
                "trimOffsets": true, "useRegex": true,
            ],
            "decoder": ["type": "ByteLevel"],
        ]
        if !added.isEmpty { data["addedTokens"] = added }
        return try JSONDecoder().decode(
            Config.self, from: JSONSerialization.data(withJSONObject: data))
    }
}
