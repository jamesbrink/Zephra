import Testing
import ZephraCore

@testable import Zephra
@testable import ZephraEngine

/// What pressing Generate, or Animate, would do first, when the model that would run is not
/// the one resident.
@Suite("what pressing Generate would do first")
struct ModelLoadNoteTests {
    @Test("nothing, when the target is already the model in use")
    func alreadyTheModelInUse() {
        let store = GenerationStore.preview(state: .ready, descriptor: ModelCatalog.zImageTurbo8bit)
        store.loadedDescriptor = ModelCatalog.zImageTurbo8bit
        #expect(ModelLoadNote.text(for: ModelCatalog.zImageTurbo8bit, store: store) == "")
    }

    @Test("names the download, with its size, when the target needs one")
    func needsDownload() {
        let store = GenerationStore.preview(state: .ready, descriptor: ModelCatalog.zImageTurbo8bit)
        store.loadedDescriptor = ModelCatalog.zImageTurbo8bit
        let target = ModelCatalog.zImageTurbo4bit
        store.availability[target.id] = .needsDownload(bytes: 13_280_000_000)
        #expect(
            ModelLoadNote.text(for: target, store: store)
                == ". Downloads 13.3 GB for \(target.fullName) first")
    }

    @Test("names the download's size for a target that also needs a build")
    func needsDownloadAndBuild() {
        let store = GenerationStore.preview(state: .ready, descriptor: ModelCatalog.zImageTurbo8bit)
        store.loadedDescriptor = ModelCatalog.zImageTurbo8bit
        let target = ModelCatalog.zImageTurbo4bit
        store.availability[target.id] = .needsDownloadAndBuild(bytes: 7_000_000_000)
        #expect(
            ModelLoadNote.text(for: target, store: store)
                == ". Downloads 7 GB for \(target.fullName) first")
    }

    @Test("names the build, when the release is here but the packed variant is not")
    func needsBuild() {
        let store = GenerationStore.preview(state: .ready, descriptor: ModelCatalog.zImageTurbo8bit)
        store.loadedDescriptor = ModelCatalog.zImageTurbo8bit
        let target = ModelCatalog.zImageTurbo4bit
        store.availability[target.id] = .needsBuild
        #expect(ModelLoadNote.text(for: target, store: store) == ". Builds \(target.fullName) first")
    }

    @Test("names the load, when the target is simply not the model resident")
    func needsOnlyALoad() {
        let store = GenerationStore.preview(state: .ready, descriptor: ModelCatalog.zImageTurbo8bit)
        store.loadedDescriptor = ModelCatalog.zImageTurbo8bit
        let target = ModelCatalog.zImageTurbo4bit
        store.availability[target.id] = .available
        #expect(ModelLoadNote.text(for: target, store: store) == ". Loads \(target.fullName) first")
    }
}
