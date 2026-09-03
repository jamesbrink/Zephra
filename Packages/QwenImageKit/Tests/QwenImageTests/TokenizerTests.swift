import Foundation
import Testing

@testable import QwenImage

/// The prompt wrapper and the tokenizer that turns it into ids.
@Suite("Tokenizer")
struct TokenizerTests {
    @Test("the template's own tokens are exactly the ones the drop index removes")
    func dropIndexMatchesTheTemplate() throws {
        guard let snapshot = SnapshotUnderTest.directory else { return }
        let tokenizer = try QwenImageTokenizer(snapshot: snapshot)

        // The wrapper's leading half -- everything before the prompt -- must be exactly
        // dropIndex tokens long, because that is the count the conditioning throws away. If the
        // template text and this number ever disagree, every conditioning vector shifts by a
        // token and the model quietly follows the prompt less well.
        let prefix = QwenImagePromptTemplate.text.components(separatedBy: "{}")[0]
        #expect(tokenizer.encode(prefix).count == QwenImagePromptTemplate.dropIndex)
    }

    @Test("a prompt is wrapped in the system message, and its own tokens follow the prefix")
    func promptSitsAfterThePrefix() throws {
        guard let snapshot = SnapshotUnderTest.directory else { return }
        let tokenizer = try QwenImageTokenizer(snapshot: snapshot)

        let wrapped = tokenizer.encode(prompt: "a red cube")
        #expect(wrapped.count > QwenImagePromptTemplate.dropIndex)
        let kept = Array(wrapped.dropFirst(QwenImagePromptTemplate.dropIndex))
        let bare = tokenizer.encode("a red cube")
        #expect(
            kept.starts(with: bare),
            "after the prefix is dropped the prompt's own tokens should come first")
    }

    @Test("a long prompt is cut after the limit, and what is kept is unchanged by the cut")
    func longPromptsAreCutAtTheLimit() throws {
        guard let snapshot = SnapshotUnderTest.directory else { return }
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

    @Test("the template markers survive as single special tokens")
    func specialTokensAreWhole() throws {
        guard let snapshot = SnapshotUnderTest.directory else { return }
        let tokenizer = try QwenImageTokenizer(snapshot: snapshot)
        // These live in added_tokens.json rather than vocab.json; without them the template
        // shatters into ordinary text and the prefix count changes.
        #expect(tokenizer.encode("<|im_start|>").count == 1)
        #expect(tokenizer.encode("<|im_end|>").count == 1)
    }
}
