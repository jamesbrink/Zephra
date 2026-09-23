import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraQuantization

/// What a quantized snapshot inherits from the full-precision one it was built from: the
/// configs, the tokenizer, the scheduler, and the VAE, but none of the weights the quantizer
/// rewrites. The fixture is shaped like a hub snapshot, where every file is a relative symlink
/// into the blob store.
@Suite("Snapshot ancillary files")
struct SnapshotAncillaryFilesTests {
    @Test("configs, tokenizer, scheduler, and the VAE come across")
    func copiesEverythingButTheWeights() throws {
        let scratch = try Self.hubSnapshot()
        try SnapshotAncillaryFiles.copy(
            from: scratch.url("source"), to: scratch.url("out"), plan: Self.plan())

        for path in [
            "out/model_index.json",
            "out/transformer/config.json",
            "out/text_encoder/config.json",
            "out/tokenizer/tokenizer.json",
            "out/scheduler/scheduler_config.json",
            "out/vae/config.json",
            "out/vae/diffusion_pytorch_model.safetensors",
        ] {
            #expect(scratch.hasFile(path), "\(path) should have been copied")
        }
    }

    @Test("symlinks into the blob store are resolved, so the copy stands on its own")
    func resolvesSymlinksToRealFiles() throws {
        let scratch = try Self.hubSnapshot()
        try SnapshotAncillaryFiles.copy(
            from: scratch.url("source"), to: scratch.url("out"), plan: Self.plan())

        // Deleting the blobs the source pointed at must not empty the copy out.
        try FileManager.default.removeItem(at: scratch.url("blobs"))
        #expect(scratch.hasFile("out/transformer/config.json"))
        #expect(
            try String(contentsOf: scratch.url("out/transformer/config.json"), encoding: .utf8)
                == #"{"kind":"transformer"}"#
        )
        #expect(
            try Self.isSymbolicLink(scratch.url("out/vae/diffusion_pytorch_model.safetensors"))
                == false,
            "a link left inside the VAE would point at a blob store the new snapshot has not got"
        )
    }

    @Test("the weights the quantizer rewrites are left to the shard writer")
    func leavesTheQuantizedWeightsAlone() throws {
        let scratch = try Self.hubSnapshot()
        try SnapshotAncillaryFiles.copy(
            from: scratch.url("source"), to: scratch.url("out"), plan: Self.plan())

        #expect(scratch.hasFile("out/transformer/model-00001-of-00002.safetensors") == false)
        #expect(scratch.hasFile("out/text_encoder/model.safetensors") == false)
        #expect(
            scratch.hasFile("out/transformer/model.safetensors.index.json") == false,
            "the index describes a shard layout the quantized component no longer has"
        )
        #expect(
            scratch.hasFile("out/quantization.json") == false,
            "the manifest is written after the copy, from the layers actually packed"
        )
        #expect(scratch.hasFile("out/stray.safetensors") == false)
    }

    @Test("a plan carrying a notice writes it beside the weights")
    func aNoticeIsWritten() throws {
        let scratch = try Self.hubSnapshot()
        let notice = "Qwen is licensed under the Qwen RESEARCH LICENSE AGREEMENT.\n"
        try SnapshotAncillaryFiles.copy(
            from: scratch.url("source"), to: scratch.url("out"),
            plan: try Self.plan(notice: notice))

        #expect(
            try String(contentsOf: scratch.url("out/NOTICE"), encoding: .utf8) == notice,
            "a license that requires a NOTICE beside a redistribution gets one from the plan")
    }

    @Test("a plan with no notice writes no NOTICE file")
    func noNoticeWritesNothing() throws {
        let scratch = try Self.hubSnapshot()
        try SnapshotAncillaryFiles.copy(
            from: scratch.url("source"), to: scratch.url("out"), plan: Self.plan())

        #expect(scratch.hasFile("out/NOTICE") == false)
    }

    /// A plan shaped like any two-component diffusion snapshot: the transformer and the text
    /// encoder hold weights worth packing, and everything else comes across whole.
    private static func plan(notice: String? = nil) throws -> QuantizationPlan {
        let precision = try QuantizationPrecision(bits: 4, groupSize: 64)
        return QuantizationPlan(
            components: [
                QuantizedComponent(directoryName: "transformer", fallback: precision),
                QuantizedComponent(directoryName: "text_encoder", fallback: precision),
            ],
            verbatimDirectories: ["tokenizer", "scheduler", "vae"],
            notice: notice
        )
    }

    /// A source tree laid out the way the hub cache lays one out: real bytes under `blobs`, and
    /// relative symlinks to them everywhere else.
    private static func hubSnapshot() throws -> Scratch {
        let scratch = Scratch("SnapshotAncillaryFiles")
        // The quantizer creates the destination before it copies anything into it.
        try scratch.make("out", isDirectory: true)
        try scratch.write(#"{"kind":"transformer"}"#, to: "blobs/transformer-config")
        try scratch.write("{}", to: "blobs/generic")
        try scratch.write("weights", to: "blobs/weights")

        try scratch.link("source/model_index.json", to: "../blobs/generic")
        try scratch.link("source/quantization.json", to: "../blobs/generic")
        try scratch.link("source/stray.safetensors", to: "../blobs/weights")

        try scratch.link("source/transformer/config.json", to: "../../blobs/transformer-config")
        try scratch.link(
            "source/transformer/model.safetensors.index.json", to: "../../blobs/generic")
        try scratch.link(
            "source/transformer/model-00001-of-00002.safetensors", to: "../../blobs/weights")
        try scratch.link("source/text_encoder/config.json", to: "../../blobs/generic")
        try scratch.link("source/text_encoder/model.safetensors", to: "../../blobs/weights")
        try scratch.link("source/tokenizer/tokenizer.json", to: "../../blobs/generic")
        try scratch.link("source/scheduler/scheduler_config.json", to: "../../blobs/generic")
        try scratch.link("source/vae/config.json", to: "../../blobs/generic")
        try scratch.link(
            "source/vae/diffusion_pytorch_model.safetensors", to: "../../blobs/weights")
        return scratch
    }

    private static func isSymbolicLink(_ url: URL) throws -> Bool {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false))
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }
}
