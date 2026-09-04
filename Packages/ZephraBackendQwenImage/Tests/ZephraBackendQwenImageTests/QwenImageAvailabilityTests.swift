import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraBackendQwenImage

@Suite("Availability is answered from the disk alone")
struct QwenImageAvailabilityTests {
    @Test("a Mac with nothing cached is told the download and the build, adapter included")
    func nothingCachedNeedsBothAndSaysSo() async throws {
        let scratch = Scratch("QwenAvailability")
        let descriptor = Self.hub()
        #expect(
            await QwenImageBackend().availability(
                of: descriptor, locations: ModelLocations(root: scratch.url("models")))
                == .needsDownloadAndBuild(bytes: 66))
        #expect(descriptor.transferBytes == 66, "the release and the adapter, not just the release")
    }

    @Test("the release without its adapter is still a download, of the adapter alone")
    func aReleaseWithoutItsAdapterFetchesOnlyTheAdapter() async throws {
        let scratch = Scratch("QwenAvailability")
        try Self.release(scratch, at: "models/Downloads/nobody--no-such-model")

        #expect(
            await QwenImageBackend().availability(
                of: Self.hub(), locations: ModelLocations(root: scratch.url("models")))
                == .needsDownloadAndBuild(bytes: 22),
            "the release is here, so only the 22 bytes of distillation are still to come")
    }

    @Test("the release with its adapter beside it means a build and no network")
    func aReleaseAndItsAdapterNeedOnlyABuild() async throws {
        let scratch = Scratch("QwenAvailability")
        try Self.release(scratch, at: "models/Downloads/nobody--no-such-model")
        try scratch.make("models/Downloads/nobody--no-such-lora/lightning.safetensors")

        #expect(
            await QwenImageBackend().availability(
                of: Self.hub(), locations: ModelLocations(root: scratch.url("models")))
                == .needsBuild)
    }

    @Test("once the variant is packed, the release and the adapter are beside the point")
    func aPackedVariantIsAvailable() async throws {
        let scratch = Scratch("QwenAvailability")
        try Self.packed(scratch, at: "models/qwen-availability-test")

        #expect(
            await QwenImageBackend().availability(
                of: Self.hub(), locations: ModelLocations(root: scratch.url("models")))
                == .available)
    }

    @Test("a directory built by hand elsewhere is available where it stands")
    func aLocalDirectory() async throws {
        let scratch = Scratch("QwenAvailability")
        let directory = try scratch.make("built", isDirectory: true)
        let descriptor = Self.local(at: directory)
        let backend = QwenImageBackend()
        let locations = ModelLocations(root: scratch.url("models"))

        let before = await backend.availability(of: descriptor, locations: locations)
        #expect(before.reason?.contains("quantization.json") == true)
        try Self.packed(scratch, at: "built")
        #expect(await backend.availability(of: descriptor, locations: locations) == .available)
    }

    /// A Qwen-shaped model from repositories that do not exist, so no cache can answer for them.
    private static func hub() -> ModelDescriptor {
        Self.descriptor(
            source: .huggingFace(
                repoID: "nobody/no-such-model", revision: "main", filePatterns: ["*"]),
            adapters: [
                ModelAdapter(
                    repoID: "nobody/no-such-lora", file: "lightning.safetensors", bytes: 22)
            ])
    }

    private static func local(at directory: URL) -> ModelDescriptor {
        Self.descriptor(source: .localDirectory(directory), adapters: [])
    }

    private static func descriptor(
        source: ModelSource, adapters: [ModelAdapter]
    ) -> ModelDescriptor {
        let base = ModelCatalog.qwenImage2512_4bit
        return ModelDescriptor(
            id: "qwen-availability-test", displayName: base.displayName, variantName: nil,
            backend: .qwenImage, source: source, quantization: .int4, downloadBytes: 44,
            residentBytes: base.residentBytes, peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes, maxPromptTokens: base.maxPromptTokens,
            capabilities: base.capabilities, builtBytes: 21, adapters: adapters)
    }

    /// A directory holding what a packed Qwen-Image variant must have.
    private static func packed(_ scratch: Scratch, at path: String) throws {
        try scratch.write("{}", to: "\(path)/model_index.json")
        try scratch.write("{}", to: "\(path)/quantization.json")
        for part in ["transformer", "text_encoder", "vae", "tokenizer", "scheduler"] {
            try scratch.make("\(path)/\(part)", isDirectory: true)
        }
    }

    /// A directory holding every entry the packer reads out of the bf16 release, with indexes
    /// naming shards that are all there.
    private static func release(_ scratch: Scratch, at path: String) throws {
        let index = """
            {"transformer": ["diffusers", "QwenImageTransformer2DModel"], \
            "text_encoder": ["transformers", "Qwen2_5_VLForConditionalGeneration"], \
            "vae": ["diffusers", "AutoencoderKLQwenImage"]}
            """
        try scratch.write(index, to: "\(path)/model_index.json")
        try scratch.write("{}", to: "\(path)/scheduler/scheduler_config.json")
        try scratch.write("{}", to: "\(path)/tokenizer/tokenizer_config.json")
        try scratch.write("{}", to: "\(path)/tokenizer/vocab.json")
        for part in ["transformer", "text_encoder"] {
            try scratch.write("{}", to: "\(path)/\(part)/config.json")
            try scratch.write("x", to: "\(path)/\(part)/model.safetensors")
        }
        try scratch.write(
            #"{"weight_map": {"a": "model.safetensors"}}"#,
            to: "\(path)/text_encoder/model.safetensors.index.json")
        try scratch.write(
            #"{"weight_map": {"a": "model.safetensors"}}"#,
            to: "\(path)/transformer/diffusion_pytorch_model.safetensors.index.json")
        try scratch.write("{}", to: "\(path)/vae/config.json")
        try scratch.write("x", to: "\(path)/vae/diffusion_pytorch_model.safetensors")
    }
}
