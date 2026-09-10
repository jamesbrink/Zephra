import Foundation
import Testing
import ZephraSnapshot
import ZephraTestSupport

@testable import ZephraBackendWan

@Suite("the Wan 2.2 snapshot shapes")
struct LocalSnapshotWanTests {
    @Test("the release list names every weight file the plan reads, and the tokenizer")
    func releaseEntries() {
        let entries = LocalSnapshot.wanRelease.requiredEntries
        #expect(entries.contains("transformer/diffusion_pytorch_model.safetensors"))
        #expect(entries.contains("vae/diffusion_pytorch_model.safetensors"))
        #expect(entries.contains("text_encoder/model-00003-of-00003.safetensors"))
        #expect(entries.contains("tokenizer/tokenizer.json"))
        // What is fetched for what it says is not required, so a download missing only the
        // README still reads as a release to build from.
        #expect(!entries.contains("README.md"))
    }

    @Test("a built directory is incomplete until the manifest lands")
    func builtNeedsManifest() throws {
        let scratch = Scratch()
        for entry in LocalSnapshot.wan.requiredEntries where entry != "quantization.json" {
            if entry.hasSuffix(".json") {
                _ = try scratch.write("{}", to: entry)
            } else {
                _ = try scratch.make(entry, isDirectory: true)
            }
        }
        #expect(LocalSnapshot.wan.missingEntry(in: scratch.root) == "quantization.json")
    }
}
