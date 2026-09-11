import Foundation
import Testing
import ZephraCore
@testable import ZephraLinkProtocol

@Suite("A queue row is the run's settings, with no picture in it")
struct QueuedEntryTests {
    /// Settings holding both kinds of pixels a run can carry.
    static var withPixels: GenerationSettings {
        var settings = LinkFixtures.settings
        settings.referenceImage = Data(repeating: 0x89, count: 4096)
        settings.referenceOrigin = "lighthouse.png"
        settings.referenceStrength = 0.6
        settings.continuation = ClipContinuation(
            frames: [Data(repeating: 0x50, count: 2048)], origin: "clip.png", sourceFrameCount: 49)
        return settings
    }

    @Test("The reads a row offers are the settings read back")
    func flatReadsAreTheSettings() {
        let row = LinkFixtures.queued(id: UUID(), batchID: UUID())
        #expect(row.prompt == "a lighthouse")
        #expect(row.width == 1024)
        #expect(row.height == 1024)
        #expect(row.seed == 42)
        #expect(row.frames == 1)
    }

    @Test("The pixels are dropped when the row is made, and what they came from is kept")
    func pixelsAreDroppedOnTheWayIn() {
        let row = QueuedEntry(
            id: UUID(), batchID: UUID(), batchIndex: 0, modelID: "m", settings: Self.withPixels)
        #expect(row.settings.referenceImage == nil)
        #expect(row.settings.referenceOrigin == "lighthouse.png")
        #expect(row.settings.referenceStrength == 0.6)
        #expect(row.settings.continuation?.frames.isEmpty == true)
        #expect(row.settings.continuation?.origin == "clip.png")
        #expect(row.settings.continuation?.contextFrames == 1)
    }

    @Test("Pixels smuggled in by a peer are dropped on the way out of the decoder")
    func pixelsAreDroppedOnTheWayOut() throws {
        let hostile = """
            {"id":"9D4C0F55-2B31-4E6A-A7C8-1F0B6E3D5A24","batchID":"1E9C2A60-4E1D-4C35-9F0E-2C7B3A5D8E11",\
            "batchIndex":0,"modelID":"m","settings":\
            {"guidance":0,"prompt":"x","seed":1,"size":{"height":64,"width":64},"steps":1,\
            "referenceImage":"iVBORw0KGgo=","frames":1,"referenceStrength":1}}
            """
        let row = try LinkJSON.decode(QueuedEntry.self, from: Data(hostile.utf8))
        #expect(row.settings.referenceImage == nil)
        #expect(row.prompt == "x")
    }

    @Test("A row survives the wire whole")
    func roundTrips() throws {
        let row = QueuedEntry(
            id: UUID(), batchID: UUID(), batchIndex: 2, modelID: "m", settings: Self.withPixels)
        #expect(try LinkFixtures.roundTrip(row) == row)
    }
}
