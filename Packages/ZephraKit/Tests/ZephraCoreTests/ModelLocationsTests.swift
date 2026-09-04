import Foundation
import Testing
import ZephraCore

@Suite("The folder models are kept in")
struct ModelLocationsTests {
    private let scratch = ModelLocations(root: URL(filePath: "/tmp/zephra-models"))

    @Test("a repository is downloaded into one flat folder named after it")
    func downloadsAreOneFolderPerRepository() {
        let directory = scratch.downloads(repoID: "mzbac/Z-Image-Turbo-8bit")
        #expect(
            directory.path(percentEncoded: false)
                == "/tmp/zephra-models/Downloads/mzbac--Z-Image-Turbo-8bit/")
        #expect(directory.deletingLastPathComponent() == scratch.downloadsRoot)
    }

    @Test("a variant built here is the descriptor's own folder under the root")
    func builtIsNamedForTheDescriptor() {
        let built = scratch.built(ModelCatalog.zImageTurbo4bit)
        #expect(built.path(percentEncoded: false) == "/tmp/zephra-models/z-image-turbo-4bit/")
    }

    @Test("the default root is what a tool with no preference to read writes into")
    func defaultRootMatchesTheCatalog() {
        #expect(ModelLocations.default.root == ModelCatalog.localModelsDirectory)
    }

    @Test("a directory a descriptor names is the one place it is looked for")
    func aNamedDirectoryIsWhatTheDescriptorMeans() {
        // No catalog entry names a directory any more, but a descriptor still can — one built
        // by hand, or one `ZephraBench` was pointed at — and that folder is the one meant,
        // ahead of any same-named copy under the app's root.
        let named = URL(filePath: "/tmp/somewhere-else/z-image-turbo-4bit")
        let candidates = scratch.builtCandidates(for: Self.local(at: named))
        #expect(candidates == [named], "the folder the descriptor names is what it means, and all it means")
    }

    @Test("a model that is downloaded rather than built has only this root to be in")
    func aDownloadedModelHasOneCandidate() {
        #expect(scratch.builtCandidates(for: ModelCatalog.flux2Klein4bit) == [
            scratch.built(ModelCatalog.flux2Klein4bit)
        ])
    }

    @Test("an adapter lands in Downloads beside the release it is merged into")
    func anAdapterIsADownloadLikeAnyOther() throws {
        let adapter = try #require(ModelCatalog.qwenImage2512_4bit.adapters.first)
        #expect(
            scratch.adapter(adapter).path(percentEncoded: false)
                == "/tmp/zephra-models/Downloads/lightx2v--Qwen-Image-2512-Lightning/")
        #expect(scratch.adapterFile(adapter).lastPathComponent == adapter.file)
    }

    /// A descriptor whose weights are a directory on this Mac rather than a repository.
    private static func local(at directory: URL) -> ModelDescriptor {
        let base = ModelCatalog.zImageTurbo4bit
        return ModelDescriptor(
            id: base.id, displayName: base.displayName, variantName: base.variantName,
            backend: base.backend, source: .localDirectory(directory),
            quantization: base.quantization, downloadBytes: 0,
            residentBytes: base.residentBytes, peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes, maxPromptTokens: base.maxPromptTokens,
            capabilities: base.capabilities)
    }
}
