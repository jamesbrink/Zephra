import Foundation
import Testing
import ZephraCore
import ZephraSnapshot
import ZephraTestSupport

@Suite("Model storage")
struct ModelStorageTests {
    @Test("a release two variants pack from is listed once, naming both")
    func sharedReleaseListedOnce() throws {
        let scratch = Scratch("ModelStorage")
        let cache = scratch.url("hub")
        let locations = ModelLocations(root: scratch.url("models"))
        try scratch.make("hub/models/black-forest-labs/FLUX.2-klein-4B/model_index.json")
        try scratch.make("hub/models/black-forest-labs/FLUX.2-klein-4B/vae/model.safetensors")
        try scratch.make("models/flux2-klein-4b-4bit/quantization.json")

        let items = ModelStorage.items(for: ModelCatalog.all, cache: cache, locations: locations)
        #expect(items.count == 2)
        let release = try #require(items.first { $0.kind == .download })
        #expect(release.name == "FLUX.2 klein 4B release")
        #expect(release.modelIDs == ["flux2-klein-4b-4bit", "flux2-klein-4b-8bit"])
        #expect(release.isComplete)
        #expect(
            release.location.hasSuffix("hub/models/black-forest-labs/FLUX.2-klein-4B"),
            "a directory outside the models folder says where it really is")
        let built = try #require(items.first { $0.kind == .built })
        #expect(built.name == "FLUX.2 klein 4B · 4-bit")
        #expect(built.modelIDs == ["flux2-klein-4b-4bit"])
        #expect(built.location == "flux2-klein-4b-4bit")
    }

    @Test("the app's own download and a hub-cache copy of one release are told apart by where they are")
    func twoCopiesOfOneReleaseAreDistinguishable() throws {
        let scratch = Scratch("ModelStorage")
        let locations = ModelLocations(root: scratch.url("models"))
        try scratch.make("hub/models/black-forest-labs/FLUX.2-klein-4B/model_index.json")
        try scratch.make(
            "models/Downloads/black-forest-labs--FLUX.2-klein-4B/model_index.json")

        let items = ModelStorage.items(
            for: [ModelCatalog.flux2Klein4bit], cache: scratch.url("hub"), locations: locations)
        #expect(items.count == 2)
        #expect(
            items.first?.location == "Downloads/black-forest-labs--FLUX.2-klein-4B",
            "the app's own folder is listed first, by its short path")
        #expect(items.last?.location.hasPrefix("/") == true)
    }

    @Test("an adapter `hf download` put in the cache is listed with its model, where it is")
    func aCachedAdapterIsListed() throws {
        let scratch = Scratch("ModelStorage")
        let descriptor = ModelCatalog.qwenImage2512_4bit
        let adapter = try #require(descriptor.adapters.first)
        let repository = "hub/models--" + adapter.repoID.replacingOccurrences(of: "/", with: "--")
        try scratch.write("abc", to: repository + "/refs/main")
        try scratch.make(repository + "/snapshots/abc/" + adapter.file)

        let items = ModelStorage.items(
            for: [descriptor], cache: scratch.url("hub"),
            locations: ModelLocations(root: scratch.url("models")))
        #expect(items.count == 1)
        #expect(items.first?.name == "\(descriptor.displayName) adapter")
        #expect(items.first?.isComplete == true)
        #expect(items.first?.location.hasPrefix("/") == true)
    }

    @Test("a model named by a directory outside every root is listed there, by its whole path")
    func aDirectoryNamedModelIsListedWhereItIs() throws {
        let scratch = Scratch("ModelStorage")
        let locations = ModelLocations(root: scratch.url("models"), previous: [scratch.url("old")])
        try scratch.make("elsewhere/z-image-turbo-4bit/quantization.json")
        let base = ModelCatalog.zImageTurbo4bit
        let descriptor = ModelDescriptor(
            id: base.id, displayName: base.displayName, variantName: base.variantName,
            backend: base.backend, source: .localDirectory(scratch.url("elsewhere/z-image-turbo-4bit")),
            quantization: base.quantization, downloadBytes: 0,
            residentBytes: base.residentBytes, peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes, maxPromptTokens: base.maxPromptTokens,
            capabilities: base.capabilities)

        let items = ModelStorage.items(for: [descriptor], cache: scratch.url("hub"), locations: locations)
        #expect(items.count == 1)
        #expect(items.first?.kind == .built)
        #expect(items.first?.location.hasSuffix("elsewhere/z-image-turbo-4bit") == true)
        #expect(items.first?.location.hasPrefix("/") == true)
    }

    @Test("a download the app stopped part-way is listed as incomplete, under the model's name")
    func partialDownloadIsListed() throws {
        let scratch = Scratch("ModelStorage")
        let flat = "models/Downloads/mzbac--Z-Image-Turbo-8bit"
        try scratch.make("\(flat)/model_index.json")
        try scratch.make("\(flat)/vae/model.safetensors.incomplete")

        let items = ModelStorage.items(
            for: [ModelCatalog.zImageTurbo8bit], cache: scratch.url("hub"),
            locations: ModelLocations(root: scratch.url("models")))
        let partial = try #require(items.first)
        #expect(items.count == 1)
        #expect(partial.name == "Z-Image Turbo · 8-bit")
        #expect(!partial.isComplete)
        #expect(partial.location == "Downloads/mzbac--Z-Image-Turbo-8bit")
    }

    @Test("an adapter is listed with the model it serves, and says whether its file is there")
    func anAdapterIsListedWithItsModel() throws {
        let scratch = Scratch("ModelStorage")
        let locations = ModelLocations(root: scratch.url("models"))
        try scratch.make("models/Downloads/lightx2v--Qwen-Image-2512-Lightning", isDirectory: true)

        let items = ModelStorage.items(
            for: [ModelCatalog.qwenImage2512_4bit], cache: scratch.url("hub"),
            locations: locations)
        let adapter = try #require(items.first)
        #expect(items.count == 1)
        #expect(adapter.name == "Qwen-Image 2512 adapter")
        #expect(adapter.modelIDs == ["qwen-image-2512-4bit"])
        #expect(adapter.location == "Downloads/lightx2v--Qwen-Image-2512-Lightning")
        #expect(!adapter.isComplete, "the folder is there and the one file it wants is not")

        try scratch.make(
            "models/Downloads/lightx2v--Qwen-Image-2512-Lightning/Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors"
        )
        let again = ModelStorage.items(
            for: [ModelCatalog.qwenImage2512_4bit], cache: scratch.url("hub"),
            locations: locations)
        #expect(again.first?.isComplete == true)
    }

    @Test("nothing on disk lists nothing, and never a directory that does not exist")
    func nothingListsNothing() throws {
        let scratch = Scratch("ModelStorage")
        try FileManager.default.createDirectory(at: scratch.root, withIntermediateDirectories: true)
        let items = ModelStorage.items(
            for: ModelCatalog.all, cache: scratch.url("hub"),
            locations: ModelLocations(root: scratch.url("models")))
        #expect(items.isEmpty)
    }

    @Test("a directory is measured by its files, and a link does not count its target twice")
    func measureCountsFilesOnce() throws {
        let scratch = Scratch("ModelStorage")
        try scratch.write(String(repeating: "x", count: 10_000), to: "repo/blobs/abc")
        try scratch.link("repo/snapshots/main/model.safetensors", to: "../../blobs/abc")
        let bytes = ModelStorage.measure(scratch.url("repo"))
        #expect(bytes >= 10_000)
        #expect(bytes < 20_000, "the link must not be counted as a second copy of the blob")
    }
}
