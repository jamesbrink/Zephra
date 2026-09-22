import Foundation
import Testing
import ZephraCore
import ZephraSnapshot
import ZephraTestSupport

@Suite("Model storage, retired directories")
struct ModelStorageRetiredTests {
    @Test("a packed variant no catalog entry names is listed, as retired")
    func retiredVariantIsListed() throws {
        let scratch = Scratch("ModelStorageRetired")
        try scratch.make("models/old-model/quantization.json")

        let items = ModelStorage.items(
            for: [], cache: scratch.url("hub"), locations: ModelLocations(root: scratch.url("models")))
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.origin == .retired)
        #expect(item.kind == .built)
        #expect(item.modelIDs.isEmpty)
    }

    @Test("a download no catalog entry names is listed under the repository it came from")
    func retiredDownloadIsListedByRepository() throws {
        let scratch = Scratch("ModelStorageRetired")
        try scratch.make("models/Downloads/org--repo/config.json")

        let items = ModelStorage.items(
            for: [], cache: scratch.url("hub"), locations: ModelLocations(root: scratch.url("models")))
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.name == "org/repo")
        #expect(item.kind == .download)
        #expect(item.origin == .retired)
    }

    @Test("a build in flight is not listed")
    func partialBuildIsNotListed() throws {
        let scratch = Scratch("ModelStorageRetired")
        try scratch.make("models/old-model.partial/quantization.json")

        let items = ModelStorage.items(
            for: [], cache: scratch.url("hub"), locations: ModelLocations(root: scratch.url("models")))
        #expect(items.isEmpty)
    }

    @Test("a folder of the person's own is not listed")
    func personalFolderIsNotListed() throws {
        let scratch = Scratch("ModelStorageRetired")
        try scratch.write("whatever", to: "models/Notes/whatever.txt")
        try scratch.make("models/Empty Notes", isDirectory: true)

        let items = ModelStorage.items(
            for: [], cache: scratch.url("hub"), locations: ModelLocations(root: scratch.url("models")))
        #expect(items.isEmpty)
    }

    @Test("a directory the catalog claims is listed once, by its model's name")
    func claimedDirectoryIsNotListedTwice() throws {
        let scratch = Scratch("ModelStorageRetired")
        try scratch.make("models/flux2-klein-4b-4bit/quantization.json")

        let items = ModelStorage.items(
            for: [ModelCatalog.flux2Klein4bit], cache: scratch.url("hub"),
            locations: ModelLocations(root: scratch.url("models")))
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.name == ModelCatalog.flux2Klein4bit.fullName)
        #expect(!item.modelIDs.isEmpty)
        #expect(item.origin != .retired)
    }

    @Test("an orphan under a previous root says its whole path")
    func orphanUnderPreviousRootSaysItsWholePath() throws {
        let scratch = Scratch("ModelStorageRetired")
        let locations = ModelLocations(root: scratch.url("models"), previous: [scratch.url("old")])
        try scratch.make("old/orphan-variant/quantization.json")

        let items = ModelStorage.items(for: [], cache: scratch.url("hub"), locations: locations)
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.origin == .retired)
        #expect(item.location.hasPrefix("/") == true)
        #expect(item.location.hasSuffix("old/orphan-variant") == true)
    }

    @Test("a link is not listed")
    func linkedVariantIsNotListed() throws {
        let scratch = Scratch("ModelStorageRetired")
        try scratch.make("elsewhere/real-variant/quantization.json")
        try scratch.link("models/link-variant", to: "../elsewhere/real-variant")

        let items = ModelStorage.items(
            for: [], cache: scratch.url("hub"), locations: ModelLocations(root: scratch.url("models")))
        #expect(items.isEmpty)
    }
}
