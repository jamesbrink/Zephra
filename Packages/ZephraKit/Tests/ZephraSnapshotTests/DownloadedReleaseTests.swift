import Foundation
import Testing
import ZephraCore
import ZephraSnapshot
import ZephraTestSupport

@Suite("Where a model's download already is")
struct DownloadedReleaseTests {
    let check = LocalSnapshot(
        requiredEntries: ["model_index.json", "transformer", "text_encoder", "vae"])

    @Test("nothing on disk is not a download, whatever the folder is called")
    func nothingIsNotADownload() {
        let scratch = Scratch("Downloaded")
        #expect(
            check.downloadedRelease(
                of: Self.model(), in: ModelLocations(root: scratch.url("models"))) == nil)
    }

    @Test("a finished download in the folder models are kept in is the answer")
    func theModelsFolderComesFirst() throws {
        let scratch = Scratch("Downloaded")
        let locations = ModelLocations(root: scratch.url("models"))
        try Self.snapshot(scratch, at: "models/Downloads/org--repo")

        #expect(
            check.downloadedRelease(of: Self.model(), in: locations)
                == locations.downloads(repoID: "org/repo"))
    }

    @Test("a download stopped part-way is not a download: choosing the model resumes it")
    func anIncompleteTransferIsNotADownload() throws {
        let scratch = Scratch("Downloaded")
        try Self.snapshot(scratch, at: "models/Downloads/org--repo")
        try scratch.make("models/Downloads/org--repo/vae/model.safetensors.incomplete")

        #expect(
            check.downloadedRelease(
                of: Self.model(), in: ModelLocations(root: scratch.url("models"))) == nil)
    }

    @Test("a release is a release without its adapter, and the adapter alone is what is missing")
    func anAdapterIsAskedAboutSeparately() throws {
        let scratch = Scratch("Downloaded")
        let locations = ModelLocations(root: scratch.url("models"))
        let adapter = ModelAdapter(repoID: "org/lora", file: "lightning.safetensors", bytes: 8)
        let descriptor = Self.model(adapters: [adapter])
        try Self.snapshot(scratch, at: "models/Downloads/org--repo")

        #expect(
            check.downloadedRelease(of: descriptor, in: locations) != nil,
            "thirty gigabytes already here are not fetched again for want of the distillation")
        #expect(locations.missingAdapters(of: descriptor, cache: scratch.url("hub")) == [adapter])

        try scratch.make("models/Downloads/org--lora/lightning.safetensors")
        #expect(locations.missingAdapters(of: descriptor, cache: scratch.url("hub")).isEmpty)
    }

    @Test("an adapter `hf download` put in the cache is used from there, not fetched again")
    func aCachedAdapterIsNotMissing() throws {
        let scratch = Scratch("Downloaded")
        let locations = ModelLocations(root: scratch.url("models"))
        let adapter = ModelAdapter(repoID: "org/lora", file: "lightning.safetensors", bytes: 8)
        let descriptor = Self.model(adapters: [adapter])
        let cache = scratch.url("hub")
        try scratch.write("abc", to: "hub/models--org--lora/refs/main")
        try scratch.make("hub/models--org--lora/snapshots/abc/lightning.safetensors")

        #expect(locations.missingAdapters(of: descriptor, cache: cache).isEmpty)
        #expect(
            locations.adapterFileOnDisk(adapter, cache: cache)
                == scratch.url("hub/models--org--lora/snapshots/abc/lightning.safetensors"))
        #expect(
            locations.bytesToFetch(for: descriptor, releasePresent: false, cache: cache)
                == descriptor.downloadBytes,
            "the release is the whole of what is left to fetch")
    }

    @Test("a release and an adapter under a folder the setting used to point at are still found")
    func aPreviousRootStillCounts() throws {
        let scratch = Scratch("Downloaded")
        let locations = ModelLocations(
            root: scratch.url("new"), previous: [scratch.url("old")])
        let adapter = ModelAdapter(repoID: "org/lora", file: "lightning.safetensors", bytes: 8)
        let descriptor = Self.model(adapters: [adapter])
        try Self.snapshot(scratch, at: "old/Downloads/org--repo")
        try scratch.make("old/Downloads/org--lora/lightning.safetensors")

        #expect(
            check.downloadedRelease(of: descriptor, in: locations)?.lastPathComponent == "org--repo"
                && check.downloadedRelease(of: descriptor, in: locations)?.path(percentEncoded: false)
                    .contains("/old/Downloads/") == true)
        #expect(locations.missingAdapters(of: descriptor, cache: scratch.url("hub")).isEmpty)
        #expect(
            locations.adapterFileOnDisk(adapter, cache: scratch.url("hub"))
                == scratch.url("old/Downloads/org--lora/lightning.safetensors"))
        #expect(
            locations.builtCandidates(for: descriptor).map(\.lastPathComponent) == [descriptor.id, descriptor.id],
            "the packed variant is looked for under both roots, the current one first")
    }

    @Test("a variant packed under a folder the setting used to point at is not built again")
    func aPackedVariantUnderAPreviousRootIsFound() throws {
        let scratch = Scratch("Downloaded")
        let locations = ModelLocations(
            root: scratch.url("new"), previous: [scratch.url("old")])
        let descriptor = Self.model()
        try Self.snapshot(scratch, at: "old/\(descriptor.id)")

        #expect(check.packedVariant(of: descriptor, in: locations)?.path(percentEncoded: false)
            .contains("/old/\(descriptor.id)") == true)
        #expect(
            locations.built(descriptor).path(percentEncoded: false).contains("/new/"),
            "a build that does happen still lands under the current root")
    }

    @Test("a model that is a directory rather than a repository has no download to find")
    func aLocalDirectoryHasNoDownload() {
        let scratch = Scratch("Downloaded")
        var descriptor = Self.model()
        descriptor = ModelDescriptor(
            id: descriptor.id, displayName: descriptor.displayName, variantName: nil,
            backend: descriptor.backend, source: .localDirectory(scratch.url("built")),
            quantization: descriptor.quantization, downloadBytes: 0,
            residentBytes: descriptor.residentBytes, peakBytes: descriptor.peakBytes,
            tiledPeakBytes: descriptor.tiledPeakBytes,
            maxPromptTokens: descriptor.maxPromptTokens, capabilities: descriptor.capabilities)
        #expect(
            check.downloadedRelease(
                of: descriptor, in: ModelLocations(root: scratch.url("models"))) == nil)
    }

    /// A model from a repository no cache can answer for.
    static func model(revision: String = "main", adapters: [ModelAdapter] = []) -> ModelDescriptor {
        let base = ModelCatalog.default
        return ModelDescriptor(
            id: "downloaded-test", displayName: base.displayName, variantName: base.variantName,
            backend: base.backend,
            source: .huggingFace(repoID: "org/repo", revision: revision, filePatterns: ["*"]),
            quantization: base.quantization, downloadBytes: 9,
            residentBytes: base.residentBytes, peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes, maxPromptTokens: base.maxPromptTokens,
            capabilities: base.capabilities, builtBytes: 4, adapters: adapters)
    }

    /// A directory holding what a loader opens, with an index naming its components the way a
    /// real snapshot's does — which is what the completeness check holds it to.
    static func snapshot(_ scratch: Scratch, at path: String) throws {
        let index = """
            {"transformer": ["diffusers", "Transformer"], \
            "text_encoder": ["transformers", "Encoder"], "vae": ["diffusers", "AutoencoderKL"]}
            """
        try scratch.write(index, to: "\(path)/model_index.json")
        for part in ["transformer", "text_encoder", "vae"] {
            try scratch.write("{}", to: "\(path)/\(part)/config.json")
            try scratch.write("x", to: "\(path)/\(part)/model.safetensors")
        }
    }
}
