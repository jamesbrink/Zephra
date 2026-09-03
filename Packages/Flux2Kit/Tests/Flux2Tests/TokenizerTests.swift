import Foundation
import Testing

@testable import Flux2

@Suite("The tokenizer wraps a prompt the way the reference pipeline does")
struct TokenizerTests {
    @Test("the wrapper is the rendered chat template with thinking off")
    func templateText() {
        #expect(
            Flux2PromptTemplate.wrapping("a red door")
                == "<|im_start|>user\na red door<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
    }

    @Test("the wrapper's markers are single tokens and the prompt sits between them",
          .enabled(if: SnapshotUnderTest.isPresent))
    func markersAreSingleTokens() throws {
        let tokenizer = try Flux2Tokenizer(snapshot: try #require(SnapshotUnderTest.directory))
        let ids = tokenizer.encode(prompt: "a red door")
        // <|im_start|> user \n a red door <|im_end|> \n <|im_start|> assistant \n <think> \n\n
        // </think> \n\n — the exact ids Qwen3's tokenizer gives the rendered template.
        #expect(ids.first == 151_644, "<|im_start|>")
        #expect(ids.contains(151_645), "<|im_end|>")
        #expect(ids.contains(151_667) && ids.contains(151_668), "<think> and </think>")
        #expect(tokenizer.decode(ids) == Flux2PromptTemplate.wrapping("a red door"))
    }

    @Test("padding fills to the sequence length on the right and reports where the prompt ends",
          .enabled(if: SnapshotUnderTest.isPresent))
    func paddingIsOnTheRight() throws {
        let tokenizer = try Flux2Tokenizer(snapshot: try #require(SnapshotUnderTest.directory))
        let (ids, validCount) = tokenizer.padded(prompt: "a red door", to: 512)
        #expect(ids.count == 512)
        #expect(validCount == tokenizer.encode(prompt: "a red door").count)
        #expect(ids[validCount...].allSatisfy { $0 == Flux2PromptTemplate.padTokenID })
        #expect(Array(ids[..<validCount]) == tokenizer.encode(prompt: "a red door"))
    }

    @Test("a prompt longer than the sequence is cut, not refused",
          .enabled(if: SnapshotUnderTest.isPresent))
    func longPromptsAreCut() throws {
        let tokenizer = try Flux2Tokenizer(snapshot: try #require(SnapshotUnderTest.directory))
        let long = Array(repeating: "lantern", count: 800).joined(separator: " ")
        let (ids, validCount) = tokenizer.padded(prompt: long, to: 512)
        #expect(ids.count == 512)
        #expect(validCount == 512)
    }
}
