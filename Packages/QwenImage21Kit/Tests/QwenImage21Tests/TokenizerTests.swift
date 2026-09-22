import Foundation
import Testing
import ZephraTestSupport

@testable import QwenImage21

@Suite("The prompt is wrapped and tokenized the way the reference pipeline does it")
struct TokenizerTests {
    private static var snapshot: URL? { SnapshotUnderTest.qwenImage21.directory }

    @Test("both templates are the reference's, character for character")
    func templatesMatchTheReference() throws {
        let fixture = try TokenizerFixture.load()
        #expect(QwenImage21PromptTemplate.systemPrompt == fixture.sysPrompt)
        #expect(QwenImage21PromptTemplate.textToImage == fixture.templateT2I)
        #expect(QwenImage21PromptTemplate.textAndImageToImage == fixture.templateTI2I)
        #expect(QwenImage21PromptTemplate.dropIndex == fixture.dropIndex)
        #expect(fixture.dropIndex == 14)
    }

    @Test("the vision marker run gains a leading space from the second picture on")
    func markerRun() {
        #expect(QwenImage21PromptTemplate.marker(for: 0) == "")
        #expect(
            QwenImage21PromptTemplate.marker(for: 1)
                == "<image1><|vision_start|><|image_pad|><|vision_end|>")
        #expect(
            QwenImage21PromptTemplate.marker(for: 3)
                == "<image1><|vision_start|><|image_pad|><|vision_end|>"
                + " <image2><|vision_start|><|image_pad|><|vision_end|>"
                + " <image3><|vision_start|><|image_pad|><|vision_end|>")
        // One image pad per picture, never one per vision token: the processor expands it.
        let three = QwenImage21PromptTemplate.wrapping("a cat", referenceCount: 3)
        #expect(three.components(separatedBy: "<|image_pad|>").count - 1 == 3)
        #expect(three.contains("a cat<|im_end|>"))
    }

    @Test("no pictures gives the text-to-image template and an empty prompt becomes a space")
    func wrapping() {
        #expect(QwenImage21PromptTemplate.wrapping("a red door").contains("\na red door<|im_end|>"))
        #expect(!QwenImage21PromptTemplate.wrapping("a red door").contains("<|image_pad|>"))
        // Qwen has no beginning-of-sequence token, so an empty prompt would leave the encoder
        // with nothing at all to read.
        #expect(QwenImage21PromptTemplate.wrapping("") == QwenImage21PromptTemplate.wrapping(" "))
    }

    @Test(
        "twenty-five prompts tokenize to the ids the reference gives them",
        .enabled(if: SnapshotUnderTest.qwenImage21.isPresent))
    func promptIDsMatchTheReference() throws {
        let tokenizer = try QwenImage21Tokenizer(snapshot: #require(Self.snapshot))
        let fixture = try TokenizerFixture.load()
        #expect(fixture.prompts.count == 25)
        for prompt in fixture.prompts {
            #expect(tokenizer.encode(prompt.text) == prompt.ids, Comment(rawValue: prompt.text))
        }
        for prompt in fixture.wrapped {
            let ours = tokenizer.encode(prompt: prompt.text)
            #expect(ours == prompt.ids, Comment(rawValue: "wrapped: \(prompt.text)"))
        }
    }

    @Test(
        "the drop index is the system turn's own token count, derived rather than trusted",
        .enabled(if: SnapshotUnderTest.qwenImage21.isPresent))
    func dropIndexIsDerived() throws {
        let tokenizer = try QwenImage21Tokenizer(snapshot: #require(Self.snapshot))
        let fixture = try TokenizerFixture.load()
        let empty = tokenizer.encode(
            QwenImage21PromptTemplate.textToImage.replacingOccurrences(of: "{}", with: ""))
        #expect(empty == fixture.templateT2IEmptyPromptIDs)
        #expect(Array(empty.prefix(14)) == fixture.systemTurnIDs)
        #expect(tokenizer.systemTurnTokenCount == 14)
        #expect(tokenizer.systemTurnTokenCount == QwenImage21PromptTemplate.dropIndex)
    }

    @Test(
        "the picture template's markers are the ids the reference gives them",
        .enabled(if: SnapshotUnderTest.qwenImage21.isPresent))
    func visionMarkersAreTheRightTokens() throws {
        let tokenizer = try QwenImage21Tokenizer(snapshot: #require(Self.snapshot))
        let fixture = try TokenizerFixture.load()
        let empty = tokenizer.encode(
            QwenImage21PromptTemplate.textAndImageToImage.replacingOccurrences(of: "{}", with: ""))
        #expect(empty == fixture.templateTI2IEmptyPromptIDs)
        // Only three of the markers are tokens; `<image1>` is ordinary text.
        #expect(empty.contains(try #require(fixture.specialIDs["<|vision_start|>"])))
        #expect(empty.contains(try #require(fixture.specialIDs["<|image_pad|>"])))
        #expect(empty.contains(try #require(fixture.specialIDs["<|vision_end|>"])))
        #expect(!tokenizer.encode("<image1>").isEmpty)
        #expect(tokenizer.encode("<image1>").count > 1, "<image1> is text, not a token")
    }

    @Test(
        "a prompt past the limit is cut from the back, keeping the system turn and the front",
        .enabled(if: SnapshotUnderTest.qwenImage21.isPresent))
    func longPromptsAreCut() throws {
        let tokenizer = try QwenImage21Tokenizer(snapshot: #require(Self.snapshot))
        let long = Array(repeating: "lantern", count: 900).joined(separator: " ")
        let limit = QwenImage21PromptTemplate.maxPromptTokens
        let cut = tokenizer.encode(long, limit: limit)
        #expect(cut.count == QwenImage21PromptTemplate.dropIndex + limit)
        #expect(cut == Array(tokenizer.encode(prompt: long).prefix(cut.count)))

        // A prompt inside the limit is untouched, tail and all.
        let short = tokenizer.encode("a red door", limit: limit)
        #expect(short == tokenizer.encode(prompt: "a red door"))
        #expect(short.count < QwenImage21PromptTemplate.dropIndex + limit)
    }

    @Test(
        "the tokenizer round-trips what it encoded",
        .enabled(if: SnapshotUnderTest.qwenImage21.isPresent))
    func decodeRoundTrips() throws {
        let tokenizer = try QwenImage21Tokenizer(snapshot: #require(Self.snapshot))
        let wrapped = QwenImage21PromptTemplate.wrapping("a red door")
        #expect(tokenizer.decode(tokenizer.encode(wrapped)) == wrapped)
    }
}
