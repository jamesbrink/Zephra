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
        let models = scratch.url("models")
        try scratch.make("hub/models/black-forest-labs/FLUX.2-klein-4B/model_index.json")
        try scratch.make("hub/models/black-forest-labs/FLUX.2-klein-4B/vae/model.safetensors")
        try scratch.make("models/flux2-klein-4b-4bit/quantization.json")

        let items = ModelStorage.items(for: ModelCatalog.all, cache: cache, builtIn: models)
        #expect(items.count == 2)
        let release = try #require(items.first { $0.kind == .download })
        #expect(release.name == "FLUX.2 klein 4B release")
        #expect(release.modelIDs == ["flux2-klein-4b-4bit", "flux2-klein-4b-8bit"])
        #expect(release.isComplete)
        let built = try #require(items.first { $0.kind == .built })
        #expect(built.name == "FLUX.2 klein 4B · 4-bit")
        #expect(built.modelIDs == ["flux2-klein-4b-4bit"])
    }

    @Test("a download the app stopped part-way is listed as incomplete, under the model's name")
    func partialDownloadIsListed() throws {
        let scratch = Scratch("ModelStorage")
        let flat = "hub/models/mzbac/Z-Image-Turbo-8bit"
        try scratch.make("\(flat)/model_index.json")
        try scratch.make("\(flat)/.cache/huggingface/download/vae/x.safetensors.abc.incomplete")

        let items = ModelStorage.items(
            for: ModelCatalog.all, cache: scratch.url("hub"), builtIn: scratch.url("models"))
        let partial = try #require(items.first)
        #expect(items.count == 1)
        #expect(partial.name == "Z-Image Turbo · 8-bit")
        #expect(!partial.isComplete)
    }

    @Test("nothing on disk lists nothing, and never a directory that does not exist")
    func nothingListsNothing() throws {
        let scratch = Scratch("ModelStorage")
        try FileManager.default.createDirectory(at: scratch.root, withIntermediateDirectories: true)
        let items = ModelStorage.items(
            for: ModelCatalog.all, cache: scratch.url("hub"), builtIn: scratch.url("models"))
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
