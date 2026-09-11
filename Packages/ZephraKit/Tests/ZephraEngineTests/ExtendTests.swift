import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Carrying a clip on: the model is chosen without loading, the tail rides in the well, and
/// the segment comes back joined onto its source.
@MainActor
@Suite("Extending a clip")
struct ExtendTests {
    static let ltx = ModelCatalog.ltx2Distilled4bit
    static let wan = ModelCatalog.wan22TI2V5B4bit

    /// A clip written into the bed's library the way an earlier run would have left it.
    private static func writeClip(
        into bed: EngineTestBed, model: ModelDescriptor, seed: UInt64 = 7
    ) throws -> (url: URL, record: GenerationRecord) {
        var settings = GenerationSettings.defaults(for: model)
        settings.prompt = "a kite over a beach"
        settings.seed = seed
        settings.frames = 49
        let image = GeneratedImage(
            pngData: MockBackend.pngData, settings: settings, modelID: model.id, duration: .seconds(9),
            video: GeneratedVideo(
                poster: MockBackend.pngData, mp4: Data("source-clip".utf8), frameCount: 49, frameRate: 24))
        let url = try bed.library.write(image)
        let record = try #require(GenerationRecord.read(from: try Data(contentsOf: url)))
        return (url, record)
    }

    private static func source(_ clip: (url: URL, record: GenerationRecord)) -> ContinuationSource {
        ContinuationSource(
            origin: clip.url.lastPathComponent, clip: .file(VideoSidecar.url(beside: clip.url)),
            record: clip.record)
    }

    @Test("extending chooses the clip's own model without loading it, and reads its default context")
    func choosesWithoutLoading() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let loads = bed.control.settings.loads
        let clip = try Self.writeClip(into: bed, model: Self.ltx)

        store.extend(Self.source(clip))
        while store.isAdoptingReference { await Task.yield() }

        #expect(store.descriptor.id == Self.ltx.id)
        #expect(store.modelAwaitsGenerate)
        #expect(bed.control.settings.loads == loads, "nothing was swapped")
        #expect(bed.clips.recorded.tailReads.map(\.frames) == [Self.ltx.capabilities.defaultContinuationFrames])
        let continuation = try #require(store.settings.continuation)
        #expect(continuation.frames.count == 9)
        #expect(continuation.origin == clip.url.lastPathComponent)
        #expect(continuation.sourceFrameCount == 49)
        #expect(store.settings.referenceImage == MockBackend.pngData, "the last frame is in the well")
        #expect(store.settings.referenceOrigin == clip.url.lastPathComponent)
        #expect(store.settings.prompt == "a kite over a beach")
        #expect(store.settings.size == ImageSize(width: 768, height: 512))
        #expect(store.settings.frames == 49)
        #expect(store.settings.referenceStrength == 0)
    }

    @Test("a Wan clip is carried on from its last frame alone")
    func wanHoldsOneFrame() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let clip = try Self.writeClip(into: bed, model: Self.wan)

        store.extend(Self.source(clip))
        while store.isAdoptingReference { await Task.yield() }

        #expect(store.descriptor.id == Self.wan.id)
        #expect(store.settings.continuation?.frames.count == 1)
        #expect(bed.clips.recorded.tailReads.map(\.frames) == [1])
    }

    @Test("a clip whose size is off the model's grid cannot be extended")
    func offGridSizeIsRefused() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        var record = try Self.writeClip(into: bed, model: Self.ltx).record
        record.width = 700
        #expect(!store.canExtend(record))
        #expect(store.canExtend(try Self.writeClip(into: bed, model: Self.ltx).record))
    }

    @Test("a picture put in the well afterwards drops the continuation")
    func aNewPictureDropsIt() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.extend(Self.source(try Self.writeClip(into: bed, model: Self.ltx)))
        while store.isAdoptingReference { await Task.yield() }
        #expect(store.settings.continuation != nil)

        store.useAsReference(MockBackend.pngData)
        #expect(store.settings.continuation == nil)
        #expect(store.settings.referenceImage == MockBackend.pngData)
    }

    @Test("the segment comes back joined onto its source, its held frames dropped, and the record says so")
    func theSegmentIsJoined() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let clip = try Self.writeClip(into: bed, model: Self.ltx)
        store.extend(Self.source(clip))
        while store.isAdoptingReference { await Task.yield() }

        store.generate()
        try await bed.waitUntil { store.history.count == 1 && store.state == .ready }
        await store.saveTask?.value

        let stitched = try #require(bed.clips.recorded.stitches.first)
        #expect(stitched.count == 2)
        #expect(stitched[0].mp4 == Data("source-clip".utf8))
        #expect(stitched[0].dropLeading == 0)
        #expect(stitched[1].mp4 == Data("segment:49".utf8))
        #expect(stitched[1].dropLeading == 9)

        let sent = try #require(bed.control.settings.lastSettings)
        #expect(sent.continuation?.frames.count == 9, "the tail reached the backend")

        let image = try #require(store.history.first)
        #expect(image.video?.frameCount == 49 + 49 - 9)
        #expect(image.video?.mp4.starts(with: Data("stitched:".utf8)) == true)
        #expect(image.settings.continuation?.frames.isEmpty == true, "history holds no tail")
        #expect(image.settings.continuation?.contextFrames == 9)
        #expect(image.settings.referenceImage == nil)

        let url = try #require(image.fileURL)
        let record = try #require(GenerationRecord.read(from: try Data(contentsOf: url)))
        #expect(record.continuedFrom == clip.url.lastPathComponent)
        #expect(record.contextFrames == 9)
        #expect(record.frameCount == 89)
        #expect(record.referenceBytes == nil)
        #expect(FileManager.default.fileExists(atPath: VideoSidecar.url(beside: url).path(percentEncoded: false)))
    }

    @Test("a source deleted meanwhile is found in Recently Deleted")
    func sourceInRecentlyDeleted() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let clip = try Self.writeClip(into: bed, model: Self.ltx)
        store.extend(Self.source(clip))
        while store.isAdoptingReference { await Task.yield() }
        try bed.library.moveToRecentlyDeleted(clip.url)

        store.generate()
        try await bed.waitUntil { store.history.count == 1 && store.state == .ready }
        #expect(bed.clips.recorded.stitches.count == 1)
        #expect(store.history.first?.video?.frameCount == 89)
    }

    @Test("a source that is gone for good fails the run and writes nothing")
    func missingSourceFails() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let clip = try Self.writeClip(into: bed, model: Self.ltx)
        store.extend(Self.source(clip))
        while store.isAdoptingReference { await Task.yield() }
        try FileManager.default.removeItem(at: clip.url)
        try FileManager.default.removeItem(at: VideoSidecar.url(beside: clip.url))

        store.generate()
        try await bed.waitUntil { if case .failed = store.state { return true } else { return false } }
        #expect(store.history.isEmpty)
        #expect(bed.clips.recorded.stitches.isEmpty)
    }

    @Test("a store with no clip reader cannot extend")
    func noReaderNoExtend() async throws {
        let bed = EngineTestBed()
        let store = GenerationStore(registry: bed.registry(), outputDirectory: bed.directory)
        #expect(!store.canExtend)
    }
}
