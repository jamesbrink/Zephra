import Foundation
import Testing
import ZephraSnapshot
import ZephraTestSupport

@testable import ZephraBackendLTX2

@Suite("the LTX-2.5 snapshot shapes")
struct LocalSnapshotLTX2Tests {
    @Test("the release list names the four weight files and the tokenizer, and nothing audio")
    func releaseEntries() {
        let entries = LocalSnapshot.ltx2Release.requiredEntries
        #expect(entries.contains("transformer-distilled.safetensors"))
        #expect(entries.contains("gemma4-12b-ltx-v1/tokenizer.json"))
        #expect(!entries.contains { $0.contains("audio") || $0.contains("vocoder") })
    }

    @Test("a built directory is incomplete until the manifest lands")
    func builtNeedsManifest() throws {
        let scratch = Scratch()
        for entry in LocalSnapshot.ltx2.requiredEntries where entry != "quantization.json" {
            if entry.hasSuffix(".json") {
                _ = try scratch.write("{}", to: entry)
            } else {
                _ = try scratch.make(entry, isDirectory: true)
            }
        }
        #expect(LocalSnapshot.ltx2.missingEntry(in: scratch.root) == "quantization.json")
    }
}
