import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraBackendFlux2

@Suite("Availability is answered from the disk alone")
struct Flux2AvailabilityTests {
    @Test("a local directory is available once every entry is there, and says what is missing until then")
    func localDirectory() async throws {
        let scratch = Scratch()
        let directory = try scratch.make("klein", isDirectory: true)
        let descriptor = ModelDescriptor(
            id: "klein-test", displayName: "klein", variantName: nil, backend: .flux2,
            source: .localDirectory(directory), quantization: .int4, downloadBytes: 0,
            residentBytes: 1, peakBytes: 2, tiledPeakBytes: 2, maxPromptTokens: 512,
            capabilities: ModelCatalog.flux2Klein4bit.capabilities)
        let backend = Flux2Backend()
        let locations = ModelLocations(root: scratch.url("models"))
        let before = await backend.availability(of: descriptor, locations: locations)
        #expect(before.reason?.contains("quantization.json") == true)
        try Self.packed(scratch, at: "klein")
        #expect(await backend.availability(of: descriptor, locations: locations) == .available)
    }

    @Test("a hub model without a cached release needs a download and a build")
    func hubModelWithNothingCached() async throws {
        let scratch = Scratch()
        let backend = Flux2Backend()
        #expect(
            await backend.availability(
                of: Self.hub(), locations: ModelLocations(root: scratch.url("models")))
                == .needsDownloadAndBuild(bytes: 16))
    }

    @Test("the release in the models folder means a build and no network")
    func aDownloadedReleaseNeedsOnlyABuild() async throws {
        let scratch = Scratch()
        let locations = ModelLocations(root: scratch.url("models"))
        try Self.release(scratch, at: "models/Downloads/nobody--no-such-model")

        #expect(await Flux2Backend().availability(of: Self.hub(), locations: locations) == .needsBuild)
    }

    @Test("once the variant is packed, the release is beside the point")
    func aPackedVariantIsAvailable() async throws {
        let scratch = Scratch()
        let locations = ModelLocations(root: scratch.url("models"))
        try Self.packed(scratch, at: "models/flux2-klein-availability-test")

        #expect(await Flux2Backend().availability(of: Self.hub(), locations: locations) == .available)
    }

    /// A klein-shaped model from a repository that does not exist, so no cache can answer for it.
    private static func hub() -> ModelDescriptor {
        ModelDescriptor(
            id: "flux2-klein-availability-test", displayName: "klein", variantName: nil,
            backend: .flux2,
            source: .huggingFace(repoID: "nobody/no-such-model", revision: "main", filePatterns: ["*"]),
            quantization: .int4, downloadBytes: 16, residentBytes: 1, peakBytes: 2,
            tiledPeakBytes: 2, maxPromptTokens: 512,
            capabilities: ModelCatalog.flux2Klein4bit.capabilities, builtBytes: 4)
    }

    /// A directory holding what a packed klein variant must have.
    private static func packed(_ scratch: Scratch, at path: String) throws {
        try scratch.write("{}", to: "\(path)/quantization.json")
        for part in ["transformer", "text_encoder", "vae", "tokenizer", "scheduler"] {
            try scratch.make("\(path)/\(part)", isDirectory: true)
        }
    }

    /// A directory holding every file the packer reads out of the klein release.
    private static func release(_ scratch: Scratch, at path: String) throws {
        for entry in [
            "model_index.json",
            "transformer/config.json", "transformer/diffusion_pytorch_model.safetensors",
            "text_encoder/config.json", "text_encoder/model.safetensors.index.json",
            "text_encoder/model-00001-of-00002.safetensors",
            "text_encoder/model-00002-of-00002.safetensors",
            "vae/config.json", "vae/diffusion_pytorch_model.safetensors",
            "tokenizer/tokenizer.json", "tokenizer/tokenizer_config.json",
            "scheduler/scheduler_config.json",
        ] {
            try scratch.write("{}", to: "\(path)/\(entry)")
        }
    }
}
