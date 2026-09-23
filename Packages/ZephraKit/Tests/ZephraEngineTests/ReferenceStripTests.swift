import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// The well as a strip of pictures: what fits, what a change settles, and what a batch of them
/// lands as.
@Suite("Several pictures in the reference well")
@MainActor
struct ReferenceStripTests {
    /// A model that reads ten pictures and conditions on them directly, which is the shape the
    /// only such family declares: several pictures and a share of the schedule are two
    /// different things.
    private static var reader: ModelDescriptor {
        let base = ModelCatalog.flux2Klein4bit
        let capabilities = base.capabilities
        return ModelDescriptor(
            id: "several-references", displayName: "Several references", variantName: nil,
            backend: base.backend, source: base.source, quantization: base.quantization,
            downloadBytes: base.downloadBytes, residentBytes: base.residentBytes,
            peakBytes: base.peakBytes, tiledPeakBytes: base.tiledPeakBytes,
            maxPromptTokens: base.maxPromptTokens,
            capabilities: ModelCapabilities(
                sizeAlignment: capabilities.sizeAlignment, sizePresets: capabilities.sizePresets,
                sizeBounds: capabilities.sizeBounds, defaultSize: capabilities.defaultSize,
                stepBounds: capabilities.stepBounds, defaultSteps: capabilities.defaultSteps,
                guidanceBounds: capabilities.guidanceBounds,
                defaultGuidance: capabilities.defaultGuidance,
                supportsNegativePrompt: capabilities.supportsNegativePrompt,
                supportsSeed: capabilities.supportsSeed, supportsReferenceImage: true,
                referenceImageCount: 1...10))
    }

    private static func picture(_ byte: UInt8, origin: String? = nil) -> ReferencePicture {
        ReferencePicture(data: Data([byte]), origin: origin)
    }

    private static func store(_ bed: EngineTestBed, model: ModelDescriptor) async -> GenerationStore {
        let store = bed.store(descriptor: model)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        return store
    }

    @Test("Use as Reference adds a picture where there is room, and replaces where there is not")
    func addsWhereThereIsRoom() async throws {
        let bed = EngineTestBed()
        let store = await Self.store(bed, model: Self.reader)

        store.useAsReference(Data([1]), origin: "one.png")
        store.useAsReference(Data([2]), origin: "two.png")
        #expect(store.settings.referenceImages.map(\.origin) == ["one.png", "two.png"])

        // The same door on a model that reads one picture replaces, as it always has.
        let single = EngineTestBed()
        let one = await Self.store(single, model: ModelCatalog.flux2Klein4bit)
        one.useAsReference(Data([1]), origin: "one.png")
        one.useAsReference(Data([2]), origin: "two.png")
        #expect(one.settings.referenceImages.map(\.origin) == ["two.png"])
    }

    @Test("a strip as long as the model reads has no room, and says so rather than dropping one")
    func fullStripRefuses() async throws {
        let bed = EngineTestBed()
        let store = await Self.store(bed, model: Self.reader)

        store.appendReferences((1...10).map { Self.picture(UInt8($0)) })
        #expect(store.settings.referenceImages.count == 10)
        #expect(store.referenceRoom == 0)
        #expect(store.referenceNote == nil, "ten fitted")

        store.appendReferences([Self.picture(11)])
        #expect(store.settings.referenceImages.count == 10)
        #expect(store.referenceNote != nil, "and the eleventh said why it did not")

        store.removeReference(at: 0)
        #expect(store.referenceNote == nil, "a change that works clears the note")
        #expect(store.settings.referenceImages.count == 9)
    }

    @Test("a picture past the byte budget is refused with a sentence")
    func theBudgetRefuses() async throws {
        let bed = EngineTestBed()
        let store = await Self.store(bed, model: Self.reader)
        let heavy = ReferencePicture(
            data: Data(repeating: 0x2A, count: ReferenceLimits.maximumTotalBytes / 2 + 1))

        store.appendReferences([heavy, heavy, heavy])
        #expect(store.settings.referenceImages.count == 1)
        #expect(store.referenceNote != nil)
    }

    @Test("taking one out renumbers the rest, and moving one reorders them")
    func removeAndMove() async throws {
        let bed = EngineTestBed()
        let store = await Self.store(bed, model: Self.reader)
        store.appendReferences([
            Self.picture(1, origin: "one.png"), Self.picture(2, origin: "two.png"),
            Self.picture(3, origin: "three.png"),
        ])

        store.removeReference(at: 1)
        #expect(store.settings.referenceImages.map(\.origin) == ["one.png", "three.png"])

        store.moveReference(from: 1, to: 0)
        #expect(store.settings.referenceImages.map(\.origin) == ["three.png", "one.png"])
        #expect(store.settings.referenceOrigin == "three.png", "the first is the first")

        store.moveReferences(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(store.settings.referenceImages.map(\.origin) == ["one.png", "three.png"])
    }

    @Test("a batch of five lands as five under one ticket, and a stale batch lands nothing")
    func aBatchLandsTogether() async throws {
        let bed = EngineTestBed()
        let store = await Self.store(bed, model: Self.reader)
        let five = (1...5).map { Self.picture(UInt8($0), origin: "\($0).png") }

        store.adoptReferences { five }
        await store.referenceRead?.value
        #expect(store.settings.referenceImages.count == 5)
        #expect(store.settings.referenceImages.map(\.origin) == five.map(\.origin))

        let release = AsyncStream<Void>.makeStream()
        let ninth = ReferencePicture(data: Data([9]), origin: "nine.png")
        store.adoptReferences {
            for await _ in release.stream {}
            return [ninth]
        }
        let stale = store.referenceRead
        _ = store.claimReference()
        release.continuation.finish()
        await stale?.value
        #expect(
            store.settings.referenceImages.count == 5,
            "a batch under a ticket a later choice replaced lands nothing")
    }

    @Test("every change clears a clip's tail, and the first picture is what a size follows")
    func changesSettle() async throws {
        let bed = EngineTestBed()
        let store = await Self.store(bed, model: Self.reader)
        store.settings.continuation = ClipContinuation(
            frames: [Data([7])], origin: "clip.png", sourceFrameCount: 49)

        store.appendReferences([Self.picture(1)])
        #expect(store.settings.continuation == nil, "a picture in the well is no clip's end")

        let size = store.settings.size
        store.appendReferences([Self.picture(2)])
        #expect(store.settings.size == size, "a later picture never moves the frame")
    }

    @Test("a model that reads no picture holds none, whichever door offers one")
    func aPlainModelHoldsNothing() async throws {
        let bed = EngineTestBed()
        let store = await Self.store(bed, model: ReferenceOriginTests.plain)

        store.useAsReference(Data([1]), origin: "one.png")
        store.appendReferences([Self.picture(2)])
        #expect(store.settings.referenceImages.isEmpty)
        #expect(store.referenceRoom == 0)
    }

    @Test("a reorder moves the strip's revision though it moves neither the ticket nor the count")
    func aReorderMovesTheRevision() async throws {
        let bed = EngineTestBed()
        let store = await Self.store(bed, model: Self.reader)
        store.appendReferences([Self.picture(1), Self.picture(2), Self.picture(3)])
        let choice = store.referenceChoice
        let revision = store.referenceRevision

        store.moveReference(from: 2, to: 0)
        #expect(store.settings.referenceImages.map(\.data) == [Data([3]), Data([1]), Data([2])])
        #expect(store.referenceChoice == choice)
        #expect(store.referenceRevision != revision, "a tile would keep its old picture")

        let moved = store.referenceRevision
        store.moveReferences(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(store.referenceRevision != moved)
    }
}
