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

    @Test("the default root is the folder the catalog's local entries are written against")
    func defaultRootMatchesTheCatalog() {
        #expect(ModelLocations.default.root == ModelCatalog.localModelsDirectory)
        let candidates = ModelLocations.default.builtCandidates(for: ModelCatalog.zImageTurbo4bit)
        #expect(candidates.count == 1, "the catalog's own folder is this root's folder")
        #expect(candidates.first == ModelLocations.default.built(ModelCatalog.zImageTurbo4bit))
    }

    @Test("a moved root is looked in first, and the catalog's own folder after it")
    func aMovedRootStillFindsWhatWasBuiltBefore() {
        let candidates = scratch.builtCandidates(for: ModelCatalog.zImageTurbo4bit)
        #expect(candidates.count == 2)
        #expect(candidates.first == scratch.built(ModelCatalog.zImageTurbo4bit))
        if case .localDirectory(let named) = ModelCatalog.zImageTurbo4bit.source {
            #expect(candidates.last == named, "the catalog's own folder stays usable")
        }
    }

    @Test("a model that is downloaded rather than built has only this root to be in")
    func aDownloadedModelHasOneCandidate() {
        #expect(scratch.builtCandidates(for: ModelCatalog.flux2Klein4bit) == [
            scratch.built(ModelCatalog.flux2Klein4bit)
        ])
    }
}
