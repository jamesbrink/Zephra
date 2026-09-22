import Foundation

/// `Fixtures/tokenizer_ids.json`, as written by `Tools/dump_tokenizer.py`.
struct TokenizerFixture: Decodable {
    /// One prompt and the ids Hugging Face's own tokenizer gave it.
    struct Prompt: Decodable {
        let text: String
        let ids: [Int]
    }

    let sysPrompt: String
    let templateT2I: String
    let templateTI2I: String
    let dropIndex: Int
    let systemTurnIDs: [Int]
    let templateT2IEmptyPromptIDs: [Int]
    let templateTI2IEmptyPromptIDs: [Int]
    let prompts: [Prompt]
    let wrapped: [Prompt]
    let specialIDs: [String: Int]

    static func load() throws -> TokenizerFixture {
        try JSONDecoder().decode(TokenizerFixture.self, from: Fixture.json("tokenizer_ids"))
    }
}
