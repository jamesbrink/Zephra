import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Making a picture larger: what it writes, what the result says about itself, and what the
/// engine is doing while it runs.
@MainActor
@Suite("Making a finished picture larger")
struct UpscaleTests {
    @Test("the result is written beside its parent, named for it and for the factor")
    func writesANamedFile() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        let parent = try Self.parent(in: bed)

        store.upscale(.file(parent), factor: 2)
        await store.settle()

        let stem = parent.deletingPathExtension().lastPathComponent
        #expect(Set(try bed.writtenFiles()) == [parent.lastPathComponent, "\(stem)-x2.png"])
        #expect(bed.upscalerControl.settings.lastFactor == 2)
    }

    @Test("the result keeps how its parent's pixels were made, and says where it came from")
    func recordCarriesTheParent() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        let parent = try Self.parent(in: bed, prompt: "a lighthouse at dusk")

        store.upscale(.file(parent), factor: 4)
        await store.settle()

        let record = try #require(GenerationRecord.read(from: try Self.result(bed, of: parent, 4)))
        #expect(record.prompt == "a lighthouse at dusk")
        #expect(record.seed == 99)
        #expect(record.steps == 9)
        #expect(record.modelID == ModelCatalog.default.id)
        #expect(record.upscaleFactor == 4)
        #expect(record.upscaledFrom == parent.lastPathComponent)
        #expect(record.batchID == nil)
    }

    @Test("the picture an edited parent was made from is copied across byte for byte")
    func referenceChunkIsCopied() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        let reference = Data((0..<300).map { UInt8($0 % 251) })
        let parent = try Self.parent(in: bed, reference: reference)

        store.upscale(.file(parent), factor: 2)
        await store.settle()

        let data = try Self.result(bed, of: parent, 2)
        #expect(GenerationRecord.read(from: data)?.referenceBytes == 300)
        #expect(GenerationRecord.reference(in: data) == reference)
    }

    @Test("an upscale of a three-picture edit carries all three chunks across")
    func everyReferenceChunkIsCopied() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        let pictures = (1...3).map {
            ReferencePicture(
                data: Data(repeating: UInt8($0), count: 40 * $0), origin: "source-\($0).png")
        }
        let parent = try Self.parent(in: bed, references: pictures)

        store.upscale(.file(parent), factor: 2)
        await store.settle()

        let data = try Self.result(bed, of: parent, 2)
        #expect(GenerationRecord.references(in: data) == pictures)
        #expect(GenerationRecord.read(from: data)?.referenceByteCounts == pictures.map(\.data.count))
    }

    @Test("the size recorded is the one the result declares, not the parent's times the factor")
    func sizeComesFromTheResult() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        let parent = try Self.parent(in: bed)

        store.upscale(.file(parent), factor: 4)
        await store.settle()

        // The parent is one pixel square and the mock hands back two, not four.
        let record = try #require(GenerationRecord.read(from: try Self.result(bed, of: parent, 4)))
        #expect(record.width == 2 && record.height == 2)
        #expect(store.current?.settings.size == ImageSize(width: 2, height: 2))
    }

    @Test("the engine passes through upscaling and comes back to ready")
    func statePassesThroughAndReturns() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.upscalerControl.update { $0.tiles = 6; $0.tileDelay = .milliseconds(10) }
        let parent = try Self.parent(in: bed)

        store.upscale(.file(parent), factor: 2)
        try await bed.waitForTile()
        #expect(store.isUpscaling)
        // Tiles are counted on the inference queue and arrive here through the pump, so the
        // first one the store has seen is a moment behind the first the upscaler reported.
        var seen: UpscaleProgressEvent?
        for _ in 0..<500 {
            if case .upscaling(let event) = store.state, event.completedTiles > 0 {
                seen = event
                break
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(seen?.totalTiles == 6)
        await store.settle()

        #expect(store.state == .ready)
        #expect(!store.isUpscaling)
        #expect(store.current?.pngData == MockUpscaler.pngData)
        #expect(store.history.count == 1)
    }

    @Test("an upscale with no model loaded returns the engine to idle, having loaded nothing")
    func fromIdleAndBack() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        let parent = try Self.parent(in: bed)
        #expect(store.state == .idle)
        #expect(store.canUpscale)

        store.upscale(.file(parent), factor: 2)
        await store.settle()

        #expect(store.state == .idle)
        #expect(bed.control.settings.loads == 0, "no model was needed")
        #expect(store.current?.pngData == MockUpscaler.pngData)
    }

    @Test("stopping an upscale mid-way leaves no file behind")
    func stoppingLeavesNothing() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.upscalerControl.update { $0.tiles = 20; $0.tileDelay = .milliseconds(10) }
        let parent = try Self.parent(in: bed)

        store.upscale(.file(parent), factor: 2)
        try await bed.waitForTile()
        store.cancel()
        #expect(store.state == .cancelling)
        await store.settle()

        #expect(store.state == .ready)
        #expect(store.current == nil)
        #expect(store.history.isEmpty)
        #expect(try bed.writtenFiles() == [parent.lastPathComponent])
    }

    @Test("a failed upscale is a notice, and the parent is exactly where it was")
    func failureIsANotice() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.upscalerControl.update { $0.error = .failed("The tile ran out of memory.") }
        let parent = try Self.parent(in: bed)
        let before = try Data(contentsOf: parent)

        store.upscale(.file(parent), factor: 2)
        await store.settle()

        #expect(store.state == .ready, "a compute failure never blanks the canvas")
        #expect(store.lastLibraryFailure?.action == .upscale)
        #expect(store.lastLibraryFailure?.message.hasPrefix("Couldn't upscale that image.") == true)
        #expect(try Data(contentsOf: parent) == before)
        #expect(try bed.writtenFiles() == [parent.lastPathComponent])
    }

    @Test("nothing offers an upscale while a generation runs, or in a build carrying none")
    func whenItCannotBeOffered() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        store.settings.prompt = "a lighthouse"
        store.settings.steps = 8
        store.generate()
        try await bed.waitForStep()
        #expect(!store.canUpscale)
        store.cancel()
        await store.settle()
        #expect(store.canUpscale)

        #expect(!bed.storeWithoutUpscaler().canUpscale)
        #expect(!GenerationStore.preview(state: .ready).canUpscale)
    }

    @Test("a second press while one is running is ignored")
    func secondPressIsIgnored() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.upscalerControl.update { $0.tiles = 20; $0.tileDelay = .milliseconds(5) }
        let parent = try Self.parent(in: bed)

        store.upscale(.file(parent), factor: 2)
        try await bed.waitForTile()
        store.upscale(.file(parent), factor: 4)
        await store.settle()

        #expect(bed.upscalerControl.settings.upscales == 1)
        #expect(bed.upscalerControl.settings.lastFactor == 2)
    }

    @Test("the result is announced, and the library then lists it with its parent's prompt")
    func theLibraryListsTheResult() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        let parent = try Self.parent(in: bed, prompt: "a harbour in the rain")
        let index = bed.index()
        index.start()
        await index.settle()
        store.onImageSaved = { url in index.insert(fileAt: url) }

        store.upscale(.file(parent), factor: 2)
        await store.settle()

        #expect(store.current?.fileURL != nil)
        #expect(index.items.count == 2)
        let stem = parent.deletingPathExtension().lastPathComponent
        let upscaled = try #require(index.items.first { $0.fileName == "\(stem)-x2.png" })
        #expect(upscaled.prompt == "a harbour in the rain")
        #expect(upscaled.size == ImageSize(width: 2, height: 2))
    }

    @Test("a picture Zephra did not make still becomes a picture Zephra did")
    func importedParentGetsAMinimalRecord() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        try FileManager.default.createDirectory(at: bed.directory, withIntermediateDirectories: true)
        let parent = bed.directory.appending(path: "holiday.png")
        try MockBackend.pngData.write(to: parent)

        store.upscale(.file(parent), factor: 4)
        await store.settle()

        let record = try #require(GenerationRecord.read(from: try Self.result(bed, of: parent, 4)))
        #expect(record.prompt.isEmpty)
        #expect(record.steps == 0)
        #expect(record.seed == 0)
        #expect(record.modelID == "real-esrgan-x4")
        #expect(record.upscaledFrom == "holiday.png")
        #expect(record.upscaleFactor == 4)
    }

    @Test("a model chosen during an upscale is loaded once the upscale is over")
    func aModelChosenMidUpscaleSwapsAfterwards() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.upscalerControl.update { $0.tiles = 20; $0.tileDelay = .milliseconds(5) }
        let other = try #require(ModelCatalog.all.first { $0.id != ModelCatalog.default.id })
        let parent = try Self.parent(in: bed)

        store.upscale(.file(parent), factor: 2)
        try await bed.waitForTile()
        store.switchModel(to: other)
        #expect(store.descriptor.id == other.id)
        #expect(store.loadedDescriptor?.id == ModelCatalog.default.id, "nothing swapped yet")
        await store.settle()
        await store.settle()

        #expect(store.state == .ready)
        #expect(store.loadedDescriptor?.id == other.id)
    }

    /// A generated picture in the bed's folder, which is what an upscale starts from.
    static func parent(
        in bed: EngineTestBed, prompt: String = "a lighthouse at dusk", reference: Data? = nil,
        references: [ReferencePicture] = []
    ) throws -> URL {
        var settings = GenerationSettings(
            prompt: prompt, size: ImageSize(width: 1024, height: 1024), steps: 9, guidance: 3,
            seed: 99)
        settings.referenceImage = reference
        if !references.isEmpty { settings.referenceImages = references }
        return try bed.library.write(
            GeneratedImage(
                pngData: MockBackend.pngData, settings: settings,
                modelID: ModelCatalog.default.id, duration: .seconds(3)))
    }

    /// The bytes of the file one upscale of `parent` wrote.
    static func result(_ bed: EngineTestBed, of parent: URL, _ factor: Int) throws -> Data {
        let stem = parent.deletingPathExtension().lastPathComponent
        return try Data(contentsOf: bed.directory.appending(path: "\(stem)-x\(factor).png"))
    }
}
