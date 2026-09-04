import Foundation
import Testing
import ZephraSnapshot
import ZephraTestSupport

@Suite("Hub token")
struct HubTokenTests {
    @Test("no token anywhere means the refusal is the repository's doing")
    func noTokenIsAGatedRepository() throws {
        let scratch = Scratch("HubToken")
        try FileManager.default.createDirectory(at: scratch.root, withIntermediateDirectories: true)
        #expect(HubToken.source(environment: [:], home: scratch.root) == nil)
        #expect(HubToken.refusalMessage(environment: [:], home: scratch.root).contains("login"))
    }

    @Test("the environment variable is named before any file")
    func environmentVariableFirst() throws {
        let scratch = Scratch("HubToken")
        try scratch.write("hf_abc", to: ".cache/huggingface/token")
        let source = HubToken.source(environment: ["HF_TOKEN": "hf_xyz"], home: scratch.root)
        #expect(source == "the HF_TOKEN environment variable")
    }

    @Test("a token file is named by its path, and an empty one does not count")
    func tokenFileIsNamed() throws {
        let scratch = Scratch("HubToken")
        try scratch.write("  \n", to: ".cache/huggingface/token")
        #expect(HubToken.source(environment: [:], home: scratch.root) == nil)

        try scratch.write("hf_abc\n", to: ".huggingface/token")
        let message = HubToken.refusalMessage(environment: [:], home: scratch.root)
        #expect(message.contains(".huggingface/token"))
        #expect(message.contains("need no token"))
    }
}
