import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraBackendZImage

@Suite("ZImage availability")
struct ZImageAvailabilityTests {
    @Test("a local directory that was never built is missing, and says what it lacks")
    func localDirectoryThatIsNotThere() async throws {
        let scratch = Scratch("ZImageAvailability")
        let descriptor = Self.local(at: scratch.url("never-built"))
        let availability = await ZImageBackend().availability(
            of: descriptor, locations: ModelLocations(root: scratch.url("models")))
        #expect(availability.isObtainable == false)
        #expect(availability.label == "Not built yet")
        #expect(availability.reason?.contains("model_index.json") == true)
    }

    @Test("a local directory with every entry the loader opens is available")
    func localDirectoryThatIsComplete() async throws {
        let scratch = Scratch("ZImageAvailability")
        try Self.snapshot(scratch, at: "built")
        let descriptor = Self.local(at: scratch.url("built"))
        #expect(
            await ZImageBackend().availability(
                of: descriptor, locations: ModelLocations(root: scratch.url("models")))
                == .available)
    }

    @Test("a model downloaded into the folder models are kept in needs no download")
    func aDownloadInTheModelsFolderIsAvailable() async throws {
        let scratch = Scratch("ZImageAvailability")
        let locations = ModelLocations(root: scratch.url("models"))
        let descriptor = Self.hub()
        let backend = ZImageBackend()
        #expect(
            await backend.availability(of: descriptor, locations: locations)
                == .needsDownload(bytes: descriptor.downloadBytes),
            "nothing is there yet, and the hub cache is not written to any more")

        try Self.snapshot(scratch, at: "models/Downloads/zephra-test--z-image")
        #expect(await backend.availability(of: descriptor, locations: locations) == .available)
    }

    @Test("a download stopped part-way still needs a download, so choosing the model resumes it")
    func aPartialDownloadIsNotAvailable() async throws {
        let scratch = Scratch("ZImageAvailability")
        let locations = ModelLocations(root: scratch.url("models"))
        let flat = "models/Downloads/zephra-test--z-image"
        try Self.snapshot(scratch, at: flat)
        try scratch.make("\(flat)/vae/model.safetensors.incomplete")

        #expect(await ZImageBackend().availability(of: Self.hub(), locations: locations).needsNetwork)
    }

    @Test("a variant packed here without its release cached needs a download and a build")
    func aBuiltVariantWithNothingCached() async throws {
        let scratch = Scratch("ZImageAvailability")
        let descriptor = Self.built()
        #expect(
            await ZImageBackend().availability(
                of: descriptor, locations: ModelLocations(root: scratch.url("models")))
                == .needsDownloadAndBuild(bytes: descriptor.downloadBytes))
    }

    @Test("the bf16 release in the models folder means a build and no network")
    func aDownloadedReleaseNeedsOnlyABuild() async throws {
        let scratch = Scratch("ZImageAvailability")
        try Self.release(scratch, at: "models/Downloads/zephra-test--z-image")

        #expect(
            await ZImageBackend().availability(
                of: Self.built(), locations: ModelLocations(root: scratch.url("models")))
                == .needsBuild)
    }

    @Test("once the variant is packed the release is beside the point")
    func aPackedVariantIsAvailable() async throws {
        let scratch = Scratch("ZImageAvailability")
        try Self.snapshot(scratch, at: "models/z-image-build-test")

        #expect(
            await ZImageBackend().availability(
                of: Self.built(), locations: ModelLocations(root: scratch.url("models")))
                == .available)
    }

    /// A model whose download is the bf16 release and whose load is what the packer makes of it.
    private static func built() -> ModelDescriptor {
        let base = ModelCatalog.zImageTurbo4bit
        return ModelDescriptor(
            id: "z-image-build-test", displayName: base.displayName,
            variantName: base.variantName, backend: base.backend,
            source: .huggingFace(
                repoID: "zephra-test/z-image", revision: "main",
                filePatterns: ["*.safetensors", "*.json", "tokenizer/*"]),
            quantization: base.quantization, downloadBytes: 33, residentBytes: base.residentBytes,
            peakBytes: base.peakBytes, tiledPeakBytes: base.tiledPeakBytes,
            maxPromptTokens: base.maxPromptTokens, capabilities: base.capabilities,
            builtBytes: 7)
    }

    /// A directory holding every entry the packer reads out of the bf16 release, with indexes
    /// naming shards that are all there.
    private static func release(_ scratch: Scratch, at path: String) throws {
        try snapshot(scratch, at: path)
        try scratch.write("{}", to: "\(path)/scheduler/scheduler_config.json")
        try scratch.write("{}", to: "\(path)/tokenizer/tokenizer.json")
        try scratch.write(
            #"{"weight_map": {"a": "model.safetensors"}}"#,
            to: "\(path)/text_encoder/model.safetensors.index.json")
        try scratch.write(
            #"{"weight_map": {"a": "model.safetensors"}}"#,
            to: "\(path)/transformer/diffusion_pytorch_model.safetensors.index.json")
        try scratch.write("x", to: "\(path)/vae/diffusion_pytorch_model.safetensors")
    }

    /// A model that is downloaded rather than built, from a repository no cache can hold.
    private static func hub() -> ModelDescriptor {
        let base = ModelCatalog.default
        return ModelDescriptor(
            id: "hub-test", displayName: base.displayName, variantName: base.variantName,
            backend: base.backend,
            source: .huggingFace(
                repoID: "zephra-test/z-image", revision: "main",
                filePatterns: ["*.safetensors", "*.json"]),
            quantization: base.quantization, downloadBytes: 13, residentBytes: base.residentBytes,
            peakBytes: base.peakBytes, tiledPeakBytes: base.tiledPeakBytes,
            maxPromptTokens: base.maxPromptTokens, capabilities: base.capabilities)
    }

    /// A directory holding what the vendored loader opens, with an index naming its components
    /// the way a real snapshot's does — which is what a completeness check holds it to.
    private static func snapshot(_ scratch: Scratch, at path: String) throws {
        let index = """
            {"transformer": ["zimage", "Transformer"], \
            "text_encoder": ["transformers", "Encoder"], "vae": ["zimage", "AutoencoderKL"]}
            """
        try scratch.write(index, to: "\(path)/model_index.json")
        for part in ["transformer", "text_encoder", "vae"] {
            try scratch.write("{}", to: "\(path)/\(part)/config.json")
            try scratch.write("x", to: "\(path)/\(part)/model.safetensors")
        }
    }

    /// The catalog's default model, pointed at a local directory instead of the hub.
    private static func local(at directory: URL) -> ModelDescriptor {
        let base = ModelCatalog.default
        return ModelDescriptor(
            id: "local-test",
            displayName: base.displayName,
            variantName: base.variantName,
            backend: base.backend,
            source: .localDirectory(directory),
            quantization: base.quantization,
            downloadBytes: 0,
            residentBytes: base.residentBytes,
            peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes,
            maxPromptTokens: base.maxPromptTokens,
            capabilities: base.capabilities
        )
    }
}
