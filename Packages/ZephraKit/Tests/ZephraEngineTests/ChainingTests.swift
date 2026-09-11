import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// A clip longer than one pass: made as passes that carry on from one another, joined once,
/// and published once.
@MainActor
@Suite("Chaining passes into one clip")
struct ChainingTests {
    static let ltx = ModelCatalog.ltx2Distilled4bit

    private static func store(_ bed: EngineTestBed) async -> GenerationStore {
        let store = bed.store(descriptor: ltx)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a kite over a beach"
        return store
    }

    @Test("a 241-frame clip runs as three passes, each carrying the last's tail, and lands as one clip")
    func threePasses() async throws {
        let bed = EngineTestBed()
        let store = await Self.store(bed)
        store.settings.frames = 241
        store.settings.seed = 100

        store.generate()
        try await bed.waitUntil { store.history.count == 1 && store.state == .ready }

        let runs = bed.control.settings
        #expect(runs.generations == 3)
        #expect(bed.clips.recorded.tailReads.map(\.frames) == [9, 9], "each pass but the last reads its tail")
        let stitched = try #require(bed.clips.recorded.stitches.first)
        #expect(stitched.map(\.dropLeading) == [0, 9, 9])
        #expect(stitched.map { String(decoding: $0.mp4, as: UTF8.self) } == ["segment:121", "segment:121", "segment:17"])
        let last = try #require(runs.lastSettings)
        #expect(last.frames == 17)
        #expect(last.seed == 102, "each pass takes the next seed")
        #expect(last.continuation?.frames.count == 9)

        let image = try #require(store.history.first)
        #expect(image.settings.frames == 241)
        #expect(image.settings.seed == 100)
        #expect(image.settings.continuation == nil, "a chain from nothing carries nothing on")
        #expect(image.video?.frameCount == 241)
        #expect(store.queue.isEmpty)
        #expect(store.chains.isEmpty)
    }

    @Test("a stop between passes keeps nothing")
    func stopDropsTheChain() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(5) }
        let store = await Self.store(bed)
        store.settings.frames = 241
        store.generate()
        try await bed.waitUntil { bed.control.settings.generations >= 2 }
        store.cancel()
        try await bed.waitUntil { store.state == .ready }
        #expect(store.history.isEmpty)
        #expect(store.chains.isEmpty)
        #expect(store.queue.isEmpty)
    }

    @Test("Extend Clip with a length past one pass joins the source and every pass")
    func extendedChain() async throws {
        let bed = EngineTestBed()
        let store = await Self.store(bed)
        var settings = GenerationSettings.defaults(for: Self.ltx)
        settings.prompt = "a kite"
        settings.frames = 49
        let url = try bed.library.write(
            GeneratedImage(
                pngData: MockBackend.pngData, settings: settings, modelID: Self.ltx.id, duration: .seconds(1),
                video: GeneratedVideo(poster: MockBackend.pngData, mp4: Data("source-clip".utf8), frameCount: 49, frameRate: 24)))
        let record = try #require(GenerationRecord.read(from: try Data(contentsOf: url)))
        store.extend(ContinuationSource(origin: url.lastPathComponent, clip: .file(VideoSidecar.url(beside: url)), record: record))
        while store.isAdoptingReference { await Task.yield() }
        store.settings.frames = 233

        store.generate()
        try await bed.waitUntil { store.history.count == 1 && store.state == .ready }

        let stitched = try #require(bed.clips.recorded.stitches.first)
        #expect(stitched.map(\.dropLeading) == [0, 9, 9])
        #expect(String(decoding: stitched[0].mp4, as: UTF8.self) == "source-clip")
        await store.saveTask?.value
        let image = try #require(store.history.first)
        // 49 from the source less the 9 held, plus 233 made in two passes.
        #expect(image.video?.frameCount == 49 - 9 + 233)
        #expect(image.settings.continuation?.origin == url.lastPathComponent)
        let written = try #require(image.fileURL.flatMap { try? Data(contentsOf: $0) })
        #expect(GenerationRecord.read(from: written)?.continuedFrom == url.lastPathComponent)
    }
}
