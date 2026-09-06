import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraQuantization

/// A release that keeps its components' shards at the top, or under a directory named
/// otherwise than the build writes it — the shape of the LTX-2.5 pack — is described by the
/// plan, not by rearranging the download.
@Suite("a component's source files")
struct ComponentSourceTests {
    @Test("named shards are read from the release root, in the order named")
    func namedShards() throws {
        let scratch = Scratch("ComponentSource")
        try scratch.write("w", to: "release/transformer-distilled.safetensors")
        try scratch.write("w", to: "release/vae_decoder.safetensors")
        let component = QuantizedComponent(
            directoryName: "transformer",
            sourceFiles: ["transformer-distilled.safetensors"],
            fallback: nil)
        #expect(
            try component.shards(in: scratch.url("release")).map(\.lastPathComponent)
                == ["transformer-distilled.safetensors"])
        #expect(component.sourceDirectoryURL(in: scratch.url("release")) == scratch.url("release/transformer"))
    }

    @Test("without named shards every safetensors file in the source directory is read")
    func directoryShards() throws {
        let scratch = Scratch("ComponentSource")
        try scratch.write("w", to: "release/gemma4-12b-ltx-v1/model.safetensors")
        try scratch.write("{}", to: "release/gemma4-12b-ltx-v1/config.json")
        let component = QuantizedComponent(
            directoryName: "text_encoder", sourceDirectory: "gemma4-12b-ltx-v1", fallback: nil)
        #expect(
            try component.shards(in: scratch.url("release")).map(\.lastPathComponent)
                == ["model.safetensors"])
    }

    @Test("a renamed source directory's configs land under the name the build writes")
    func configsFollowTheRename() throws {
        let scratch = Scratch("ComponentSource")
        try scratch.make("out", isDirectory: true)
        try scratch.write("{}", to: "release/config.json")
        try scratch.write("w", to: "release/transformer-distilled.safetensors")
        try scratch.write("{}", to: "release/gemma4-12b-ltx-v1/config.json")
        try scratch.write("{}", to: "release/gemma4-12b-ltx-v1/tokenizer.json")
        try scratch.write("w", to: "release/gemma4-12b-ltx-v1/model.safetensors")
        let plan = QuantizationPlan(
            components: [
                QuantizedComponent(
                    directoryName: "transformer",
                    sourceFiles: ["transformer-distilled.safetensors"], fallback: nil),
                QuantizedComponent(
                    directoryName: "text_encoder", sourceDirectory: "gemma4-12b-ltx-v1", fallback: nil),
            ],
            verbatimDirectories: [])
        try SnapshotAncillaryFiles.copy(from: scratch.url("release"), to: scratch.url("out"), plan: plan)
        #expect(scratch.hasFile("out/config.json"))
        #expect(scratch.hasFile("out/text_encoder/config.json"))
        #expect(scratch.hasFile("out/text_encoder/tokenizer.json"))
        #expect(!scratch.hasFile("out/text_encoder/model.safetensors"))
        #expect(!scratch.hasFile("out/gemma4-12b-ltx-v1"))
        #expect(!scratch.hasFile("out/transformer-distilled.safetensors"))
    }
}
