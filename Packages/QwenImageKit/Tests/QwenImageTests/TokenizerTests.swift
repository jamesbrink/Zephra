import Foundation
import Testing
import ZephraTestSupport

@testable import QwenImage

/// The prompt wrapper and the tokenizer that turns it into ids.
@Suite("Tokenizer")
struct TokenizerTests {
    /// What `dump_tokenizer` wrote: the Hugging Face tokenizer's ids for each prompt, and the
    /// reference pipeline's own template and count of the tokens it drops.
    private struct ReferenceIDs: Decodable {
        struct Case: Decodable {
            let text: String
            let ids: [Int]
        }
        let template: String
        let prefixCount: Int
        let cases: [Case]

        enum CodingKeys: String, CodingKey {
            case template, cases
            case prefixCount = "prefix_count"
        }
    }

    @Test("every fixture prompt encodes to the ids the reference tokenizer produced", .enabled(if: SnapshotUnderTest.qwenImage.isPresent))
    func encodesToTheReferenceIDs() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage.directory)
        let tokenizer = try QwenImageTokenizer(snapshot: snapshot)
        let reference: ReferenceIDs = try Fixture.json("tokenizer_ids")

        // Hyphens, contractions, single digits, runs of newlines, merges beginning with `#`,
        // other scripts, and a combining accent: each is a way an assembled pre-tokenizer can
        // disagree with the real one while the suite's other tests stay green.
        #expect(reference.cases.count >= 20)
        for item in reference.cases {
            #expect(tokenizer.encode(item.text) == item.ids, "\(item.text.debugDescription)")
        }
    }

    @Test("the drop index is the reference's own count of the template prefix")
    func dropIndexIsTheReferencesPrefixCount() throws {
        let reference: ReferenceIDs = try Fixture.json("tokenizer_ids")
        #expect(QwenImagePromptTemplate.dropIndex == reference.prefixCount)
        #expect(QwenImagePromptTemplate.text == reference.template)
    }

    @Test("the template's own tokens are exactly the ones the drop index removes", .enabled(if: SnapshotUnderTest.qwenImage.isPresent))
    func dropIndexMatchesTheTemplate() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage.directory)
        let tokenizer = try QwenImageTokenizer(snapshot: snapshot)

        // The wrapper's leading half -- everything before the prompt -- must be exactly
        // dropIndex tokens long, because that is the count the conditioning throws away. If the
        // template text and this number ever disagree, every conditioning vector shifts by a
        // token and the model quietly follows the prompt less well.
        let prefix = QwenImagePromptTemplate.text.components(separatedBy: "{}")[0]
        #expect(tokenizer.encode(prefix).count == QwenImagePromptTemplate.dropIndex)
    }

    @Test("a prompt is wrapped in the system message, and its own tokens follow the prefix", .enabled(if: SnapshotUnderTest.qwenImage.isPresent))
    func promptSitsAfterThePrefix() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage.directory)
        let tokenizer = try QwenImageTokenizer(snapshot: snapshot)

        let wrapped = tokenizer.encode(prompt: "a red cube")
        #expect(wrapped.count > QwenImagePromptTemplate.dropIndex)
        let kept = Array(wrapped.dropFirst(QwenImagePromptTemplate.dropIndex))
        let bare = tokenizer.encode("a red cube")
        #expect(
            kept.starts(with: bare),
            "after the prefix is dropped the prompt's own tokens should come first")
    }

    @Test("a long prompt is cut after the limit, and what is kept is unchanged by the cut", .enabled(if: SnapshotUnderTest.qwenImage.isPresent))
    func longPromptsAreCutAtTheLimit() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage.directory)
        let tokenizer = try QwenImageTokenizer(snapshot: snapshot)
        let prompt = Array(repeating: "a red cube beside a blue sphere", count: 40).joined(separator: ", ")

        let whole = tokenizer.encode(prompt: prompt)
        let cut = tokenizer.encode(prompt: prompt, limit: 16)
        #expect(whole.count > QwenImagePromptTemplate.dropIndex + 16)
        #expect(cut.count == QwenImagePromptTemplate.dropIndex + 16)
        #expect(whole.starts(with: cut))
        // A prompt inside the limit is not touched, closing markers and all.
        #expect(tokenizer.encode(prompt: "a red cube", limit: 512) == tokenizer.encode(prompt: "a red cube"))
    }

    @Test("the template markers survive as single special tokens", .enabled(if: SnapshotUnderTest.qwenImage.isPresent))
    func specialTokensAreWhole() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage.directory)
        let tokenizer = try QwenImageTokenizer(snapshot: snapshot)
        // These live in added_tokens.json rather than vocab.json; without them the template
        // shatters into ordinary text and the prefix count changes.
        #expect(tokenizer.encode("<|im_start|>").count == 1)
        #expect(tokenizer.encode("<|im_end|>").count == 1)
    }
}
