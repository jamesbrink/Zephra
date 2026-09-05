import Foundation
import Hub

extension QwenImageTokenizer {
    /// Qwen2's pre-tokenization regex, from `transformers`' `tokenization_qwen2.py`
    /// (`PRETOKENIZE_REGEX`), which is also what the converted `tokenizer.json` carries.
    ///
    /// Against GPT-2's: the letters alternative takes at most one leading character that is
    /// neither a letter nor a digit (so a hyphen or a space, but not both), and `\p{N}` takes one
    /// digit rather than a run. Those two are why "black-and-white" is three tokens, not seven,
    /// and why "12345" is five.
    static let splitPattern =
        #"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#

    /// Builds the tokenizer data `AutoTokenizer` would have read from `tokenizer.json`.
    static func assembled(in directory: URL) throws -> Config {
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
        var data: [String: Any] = [
            // Qwen2Tokenizer.prepare_for_tokenization normalises to NFC before anything else.
            "normalizer": ["type": "NFC"],
            "model": ["vocab": vocabulary, "merges": merges(in: mergesText)],
            "preTokenizer": [
                "type": "Sequence",
                "pretokenizers": [
                    [
                        "type": "Split", "pattern": ["Regex": splitPattern],
                        "behavior": "Isolated", "invert": false,
                    ],
                    [
                        "type": "ByteLevel", "addPrefixSpace": false,
                        "trimOffsets": true, "useRegex": false,
                    ],
                ],
            ],
            "decoder": ["type": "ByteLevel"],
        ]
        if !added.isEmpty { data["addedTokens"] = added }
        return try JSONDecoder().decode(
            Config.self, from: JSONSerialization.data(withJSONObject: data))
    }

    /// The merge list, read the way `Qwen2Tokenizer` reads it: only the first line is a header,
    /// and only when it says `#version:`. Ninety-six real merges begin with `#`.
    private static func merges(in text: String) -> [String] {
        text.components(separatedBy: "\n").enumerated().compactMap { index, line in
            let merge = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if merge.isEmpty || (index == 0 && merge.hasPrefix("#version:")) { return nil }
            return merge
        }
    }
}
