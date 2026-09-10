import Foundation
import MLX
import MLXNN
import Testing
import ZephraTestSupport

@testable import Wan

/// The pipeline's prompt rules: `prompt_clean` against the strings `diffusers` produced for
/// every fixture prompt, and the embedding's shape and zeroing on the doll's-house encoder
/// under a toy vocabulary, so neither needs the release on disk.
@Suite("A prompt is cleaned and encoded the way the pipeline does it")
struct PromptEncodingTests {
    @Test("every fixture prompt cleans to what diffusers' prompt_clean gave")
    func cleaningMatchesTheReference() throws {
        let reference = try TokenizerTests.reference()
        for (index, prompt) in reference.prompts.enumerated() {
            #expect(WanPromptCleaning.clean(prompt.text) == prompt.cleaned, Comment(rawValue: "prompt \(index)"))
        }
    }

    @Test("HTML references resolve as Python's html.unescape resolves them")
    func htmlReferences() {
        #expect(WanPromptCleaning.unescapingHTML("&amp;&lt;&gt;&quot;&apos;") == "&<>\"'")
        #expect(WanPromptCleaning.unescapingHTML("&#65;&#x42;&#X43;") == "ABC")
        #expect(WanPromptCleaning.unescapingHTML("&#150;") == "\u{2013}")
        #expect(WanPromptCleaning.unescapingHTML("&#xD800;&#1114112;&#0;") == "\u{FFFD}\u{FFFD}\u{FFFD}")
        #expect(WanPromptCleaning.unescapingHTML("&ampfoo &hellipx &nothing; &#x;") == "&foo &hellipx &nothing; &#x;")
        #expect(WanPromptCleaning.unescapingHTML("&amp") == "&")
        #expect(WanPromptCleaning.unescapingHTML("no references") == "no references")
        // The pipeline unescapes twice, so a doubly escaped ampersand comes all the way back.
        #expect(WanPromptCleaning.clean("&amp;amp;") == "&")
    }

    @Test("whitespace of every kind collapses to one space and the ends go")
    func whitespace() {
        #expect(WanPromptCleaning.collapsingWhitespace(" \t a \n\n b\u{A0}c\u{3000}d\u{1C}e ") == "a b c d e")
        #expect(WanPromptCleaning.collapsingWhitespace("") == "")
        #expect(WanPromptCleaning.collapsingWhitespace("   ") == "")
    }

    @Test("the embedding is [maxLength, dModel], the encoder's rows up to </s>, zero after")
    func embeddingShapeAndZeroing() throws {
        let fixture = try Fixture.load("text_encoder")
        let encoder = try TextEncoderParityTests.loaded(fixture)
        let tokenizer = try Self.toyTokenizer()
        let encoding = WanPromptEncoding(tokenizer: tokenizer, encoder: encoder)

        let embeddings = try encoding.encode("a   b &amp; a", maxLength: 12)
        #expect(embeddings.shape == [12, 32])

        let (ids, mask) = tokenizer.padded("a b & a", to: 12)
        #expect(ids == [5, 6, 4, 3, 5, 1, 0, 0, 0, 0, 0, 0])
        let tokens = MLXArray(ids.map(Int32.init))[.newAxis, 0...]
        let padding = MLXArray(mask.map(Int32.init))[.newAxis, 0...]
        let hidden = try encoder.lastHiddenState(tokens, padding: padding)[0]
        #expect(Fixture.maxAbsoluteDifference(embeddings[..<6], hidden[..<6]) == 0)
        #expect(MLX.max(MLX.abs(embeddings[6...])).item(Float.self) == 0)
        #expect(MLX.max(MLX.abs(hidden[6...])).item(Float.self) > 0)
    }

    /// A nine-piece Unigram tokenizer whose ids fit the doll's house's vocabulary of 64.
    static func toyTokenizer() throws -> WanTokenizer {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wan-toy-tokenizer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
            {"version": "1.0",
             "added_tokens": [{"id": 1, "content": "</s>", "special": true}],
             "model": {"type": "Unigram", "unk_id": 3, "byte_fallback": false, "vocab": [
               ["<pad>", 0.0], ["</s>", 0.0], ["<s>", 0.0], ["<unk>", 0.0], ["\u{2581}", -3.0],
               ["\u{2581}a", -1.0], ["\u{2581}b", -1.0], ["a", -2.0], ["b", -2.0]]}}
            """
        try Data(json.utf8).write(to: directory.appending(path: "tokenizer.json"))
        return try WanTokenizer(directory: directory)
    }
}
