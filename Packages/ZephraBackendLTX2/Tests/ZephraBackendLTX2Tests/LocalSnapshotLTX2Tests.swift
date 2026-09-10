import Foundation
import Testing
import ZephraSnapshot
import ZephraTestSupport

@testable import ZephraBackendLTX2

@Suite("the LTX-2.5 snapshot shapes")
struct LocalSnapshotLTX2Tests {
    @Test("the release list names the five weight files and the tokenizer, and nothing audio")
    func releaseEntries() {
        let entries = LocalSnapshot.ltx2Release.requiredEntries
        #expect(entries.contains("transformer-distilled.safetensors"))
        #expect(entries.contains("gemma4-12b-ltx-v1/tokenizer.json"))
        // A pack fetched before a first frame could be held has every other file and not this
        // one, and must read as a download to finish rather than as a release to build from.
        #expect(entries.contains("vae_encoder.safetensors"))
        #expect(entries.contains("spatial_upscaler_x2_v1_1.safetensors"), "the second stage doubles the latent with it")
        #expect(!entries.contains { $0.contains("audio") || $0.contains("vocoder") || $0.contains("temporal") })
    }

    @Test("a built directory names no source file, because the packer writes none of them")
    func builtNamesNoSourceFile() {
        // The packer writes each component as `model*.safetensors`; a rule naming the release's
        // own `vae_encoder.safetensors` would read every fresh build as unbuilt. What catches a
        // variant packed before the encoder was fetched is `PackedProvenance.identity`, which
        // carries the descriptor's file patterns.
        #expect(!LocalSnapshot.ltx2.requiredEntries.contains { $0.contains("vae_encoder") })
        #expect(LocalSnapshot.ltx2.requiredEntries.contains("vae"))
        #expect(LocalSnapshot.ltx2.requiredEntries.contains("upsampler"))
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
