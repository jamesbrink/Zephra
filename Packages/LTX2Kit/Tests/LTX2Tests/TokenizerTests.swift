import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import LTX2

/// The tokenizer against Hugging Face's `tokenizers` on the real `tokenizer.json`.
///
/// The fixture holds a dozen prompts -- plain, accented, CJK, emoji, empty, long enough to
/// truncate, and one that already starts with `<bos>` -- with the ids the reference produces
/// after LTX's own rules: strip, ensure `<bos>`, keep the front. The tokenizer file itself is 32
/// megabytes and not committed, so these run only where the release or its packed variant is.
@Suite("The tokenizer reproduces the reference's ids", .enabled(if: SnapshotUnderTest.ltx2.ltx2TokenizerDirectory != nil))
struct TokenizerTests {
    private static func tokenizer() throws -> LTX2Tokenizer {
        try LTX2Tokenizer(directory: try #require(SnapshotUnderTest.ltx2.ltx2TokenizerDirectory))
    }

    @Test("every fixture prompt encodes to the reference's ids")
    func idsMatch() throws {
        let fixture = try Fixture.load("tokenizer")
        let tokenizer = try Self.tokenizer()
        #expect(fixture["bos"]?.item(Int32.self) == Int32(tokenizer.bosTokenID))
        var checked = 0
        while let text = fixture["prompt\(checked).text"], let ids = fixture["prompt\(checked).ids"] {
            let prompt = String(decoding: text.asArray(UInt8.self), as: UTF8.self)
            let expected = ids.asArray(Int32.self).map(Int.init)
            let ours = tokenizer.encode(prompt)
            #expect(ours == expected, Comment(rawValue: "prompt \(checked) (\(prompt.prefix(30))...) tokenised differently"))
            checked += 1
        }
        #expect(checked == 12)
    }

    @Test("a prompt is left-padded to 1024 with a mask over the real tokens")
    func leftPadding() throws {
        let tokenizer = try Self.tokenizer()
        let (ids, mask) = tokenizer.padded("a red kite over a beach")
        #expect(ids.count == 1024)
        #expect(mask.count == 1024)
        let real = mask.reduce(0, +)
        #expect(ids.prefix(1024 - real).allSatisfy { $0 == tokenizer.padTokenID })
        #expect(ids[1024 - real] == tokenizer.bosTokenID)
        #expect(mask.prefix(1024 - real).allSatisfy { $0 == 0 })
        #expect(mask.suffix(real).allSatisfy { $0 == 1 })
    }

    @Test("a prompt longer than the limit keeps its front")
    func truncationKeepsTheFront() throws {
        let tokenizer = try Self.tokenizer()
        let long = tokenizer.encode(String(repeating: "word ", count: 2000))
        #expect(long.count == 1024)
        #expect(long.first == tokenizer.bosTokenID)
        #expect(tokenizer.padded(String(repeating: "word ", count: 2000)).mask.allSatisfy { $0 == 1 })
    }
}
