import Foundation
import Testing
import ZephraTestSupport

@testable import Wan

/// The tokenizer against `transformers` 5.16.1's `T5Tokenizer` on the release's `tokenizer.json`.
///
/// The fixture holds thirty-one prompts chosen for the ways a tokenizer goes wrong -- digits,
/// punctuation runs, hyphens and apostrophes, whitespace of every kind at every position, an
/// accented word and a combining accent, CJK, Cyrillic, Arabic, Devanagari, emoji and joiner
/// sequences, HTML entities, a literal `▁`, added tokens typed out, a prompt past 512 tokens
/// and the empty string -- with the ids the reference produces after truncation and `</s>`.
/// The tokenizer file is 16 megabytes and not committed, so these run only where the release
/// or its packed variant is.
@Suite("The tokenizer reproduces the reference's ids", .enabled(if: SnapshotUnderTest.wan.wanTokenizerDirectory != nil))
struct TokenizerTests {
    /// `tokenizer_ids.json`, as `dump_text_encoder.py` writes it.
    struct Reference: Decodable {
        struct Prompt: Decodable {
            let text: String
            let ids: [Int]
            let cleaned: String
        }
        let eosTokenId: Int
        let padTokenId: Int
        let unkTokenId: Int
        let maxLength: Int
        let prompts: [Prompt]
        enum CodingKeys: String, CodingKey {
            case eosTokenId = "eos_token_id", padTokenId = "pad_token_id", unkTokenId = "unk_token_id"
            case maxLength = "max_length", prompts
        }
    }

    /// Read once: the vocabulary takes a second to index.
    static let tokenizer: WanTokenizer? = SnapshotUnderTest.wan.wanTokenizerDirectory.flatMap {
        try? WanTokenizer(directory: $0)
    }

    static func reference() throws -> Reference {
        let url = try #require(Bundle.module.resourceURL?.appending(path: "Fixtures/tokenizer_ids.json"))
        return try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
    }

    @Test("every fixture prompt encodes to the reference's ids")
    func idsMatch() throws {
        let tokenizer = try #require(Self.tokenizer)
        let reference = try Self.reference()
        #expect(reference.prompts.count >= 25)
        for (index, prompt) in reference.prompts.enumerated() {
            let ours = tokenizer.encode(prompt.text)
            #expect(ours == prompt.ids, Comment(rawValue: "prompt \(index) (\(prompt.text.prefix(30))...) tokenized differently"))
        }
    }

    @Test("the special ids are the reference's")
    func specialIDs() throws {
        let tokenizer = try #require(Self.tokenizer)
        let reference = try Self.reference()
        #expect(tokenizer.eosTokenID == reference.eosTokenId)
        #expect(tokenizer.padTokenID == reference.padTokenId)
        #expect(tokenizer.unknownTokenID == reference.unkTokenId)
        #expect(WanTokenizer.maxLength == reference.maxLength)
    }

    @Test("a prompt is right-padded to 512 with a mask over the real tokens")
    func rightPadding() throws {
        let tokenizer = try #require(Self.tokenizer)
        let (ids, mask) = tokenizer.padded("a red kite over a beach")
        #expect(ids.count == 512)
        #expect(mask.count == 512)
        let real = mask.reduce(0, +)
        #expect(real == tokenizer.encode("a red kite over a beach").count)
        #expect(real > 1 && real < 512)
        #expect(ids[real - 1] == tokenizer.eosTokenID)
        #expect(ids.suffix(512 - real).allSatisfy { $0 == tokenizer.padTokenID })
        #expect(mask.prefix(real).allSatisfy { $0 == 1 })
        #expect(mask.suffix(512 - real).allSatisfy { $0 == 0 })
    }

    @Test("a prompt longer than the limit keeps its front and still ends with </s>")
    func truncationKeepsTheFront() throws {
        let tokenizer = try #require(Self.tokenizer)
        let short = tokenizer.encode("word")
        let long = tokenizer.encode(String(repeating: "word ", count: 2000))
        #expect(long.count == 512)
        #expect(long.last == tokenizer.eosTokenID)
        #expect(long.first == short.first)
        #expect(tokenizer.padded(String(repeating: "word ", count: 2000)).mask.allSatisfy { $0 == 1 })
    }

    @Test("a character no piece covers becomes the file's <unk>, never the reference's <s>")
    func unknownCharacter() throws {
        let tokenizer = try #require(Self.tokenizer)
        // Mathematical fraktur U, which the vocabulary lacks, between two pieces it has.
        let ids = tokenizer.encode("a \u{1D518} b")
        #expect(ids.contains(tokenizer.unknownTokenID))
        #expect(!ids.contains(2))
        // Two unknown characters in a row fuse into one <unk>.
        let fused = tokenizer.encode("\u{1D518}\u{1D518}")
        #expect(fused.filter { $0 == tokenizer.unknownTokenID }.count == 1)
    }

    @Test("decoding gives the text back with the word markers as spaces")
    func decodeRoundTrip() throws {
        let tokenizer = try #require(Self.tokenizer)
        let ids = tokenizer.encode("a tin robot reading a newspaper")
        #expect(tokenizer.decode(ids) == " a tin robot reading a newspaper</s>")
    }
}
