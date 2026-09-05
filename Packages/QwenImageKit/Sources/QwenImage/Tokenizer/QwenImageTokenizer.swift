import Foundation
import Hub
import Tokenizers

/// Qwen2's byte-level BPE, assembled from the files the snapshot actually ships.
///
/// Qwen-Image publishes `vocab.json`, `merges.txt` and `added_tokens.json` but no
/// `tokenizer.json`, so `AutoTokenizer` has nothing to read and the assembly in
/// `QwenImageTokenizer+Assembly.swift` emits what the converted fast tokenizer would carry: an
/// `NFC` normalizer; a pre-tokenizer that is a `Sequence` of a `Split` on Qwen2's own regex,
/// separators kept, and then a `ByteLevel` step that maps bytes to the byte-level alphabet
/// without splitting again; and every merge in `merges.txt` but its `#version:` header line.
///
/// Two things were wrong before, and both changed which ids a prompt produced. A lone
/// `ByteLevel` pre-tokenizer with `useRegex` on splits with GPT-2's regex, which glues a leading
/// space or mark to the letters after it and takes digits in runs, where Qwen2's
/// `[^\r\n\p{L}\p{N}]?\p{L}+` takes at most one such mark and `\p{N}` takes digits one at a time;
/// "high-quality, black-and-white" came out as nine tokens instead of the reference's six. And
/// every merge line beginning `#` was dropped as if it were the header, which took 96 real
/// merges (`# #`, `## ##`, `# include`) with it, so `###` was three single bytes. `TokenizerTests`
/// pins the ids of twenty prompts against the Hugging Face tokenizer's own.
///
/// swift-transformers 0.1.24 reads a `Split`'s `pattern.Regex` and always keeps the separators,
/// ignoring `behavior`; `Isolated` is what this emits, so a later version that honours the field
/// changes nothing.
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
            tokenizerData: try Self.assembled(in: directory)
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
}
