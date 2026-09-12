import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraMobile

/// The frozen preview states are only as good as the fixture behind them, and the fixture is
/// only a fixture while it still decodes as what a Mac would send. That is what this suite is:
/// the DTOs and the JSON checked against each other on every build.
@Suite("The frozen preview fixture")
struct PreviewFixtureTests {
    @Test("The snapshot decodes as a state snapshot")
    func decodesSnapshot() throws {
        let snapshot = try #require(MobilePreview.snapshot())
        #expect(snapshot.hostName == "halcyon")
        #expect(snapshot.protocolVersion == LinkProtocolVersion.current)
        #expect(snapshot.engine.kind == .ready)
        #expect(snapshot.queue.isEmpty)
        #expect(snapshot.running == nil)
        #expect(snapshot.acceptsWork)
    }

    @Test("It holds two models, one of them the one in force")
    func holdsTwoModels() throws {
        let snapshot = try #require(MobilePreview.snapshot())
        #expect(snapshot.models.count == 2)
        #expect(snapshot.models.contains { $0.id == snapshot.model.id })
        #expect(snapshot.availability.count == 2)
    }

    @Test("It holds two finished pictures with the provenance a real one carries")
    func holdsHistory() throws {
        let snapshot = try #require(MobilePreview.snapshot())
        #expect(snapshot.history.count == 2)
        let record = try #require(snapshot.history.first?.record)
        #expect(!record.prompt.isEmpty)
        #expect(record.width == 1024)
        #expect(record.batchID != nil)
    }

    @Test("The library page decodes, and says which entry is a clip")
    func decodesLibrary() throws {
        let library = MobilePreview.library()
        #expect(library.count == 3)
        #expect(library.filter(\.isVideo).count == 1)
        // The version is the cache key, so two entries may never share one.
        #expect(Set(library.map(\.version)).count == library.count)
    }

    @Test("The mid-run state is the snapshot with a run in it")
    func swapsInARun() throws {
        let running = try #require(MobilePreview.midRun(MobilePreview.snapshot()))
        #expect(running.engine.kind == .generating)
        #expect(running.engine.isBusy)
        #expect(running.engine.step == 4)
        #expect(running.running?.modelID == running.model.id)
        #expect(running.acceptsWork, "a run in flight closes none of the Mac's gates")
        #expect(running.engine.canQueue, "and another may be queued behind it")
    }

    /// The test host launches under `ZEPHRA_PREVIEW_STATE=ready`, so this is the frozen client
    /// the screenshot builds get, checked here rather than looked at in a picture.
    @Test("The frozen client is paired, live, and holding what the fixture holds")
    func freezesAPairedClient() throws {
        let client = try #require(MobilePreview.client())
        #expect(client.pairedHost?.name == "halcyon")
        #expect(client.connection == .live(.lan))
        #expect(client.snapshot?.engine.kind == .ready)
        #expect(client.library.count == 3)
    }

    @Test("A client with no preview state behind it is paired with nobody")
    func theUnpairedOneIsUnpaired() {
        let client = MobilePreview.unpairedClient()
        #expect(client.pairedHost == nil)
        #expect(client.connection == .offline)
    }

    @Test("The mid-run state carries a frame for the canvas to draw")
    func theMidRunStateHasAFrame() {
        let frame = MobilePreview.frame()
        #expect(frame.jpeg.prefix(2) == Data([0xFF, 0xD8]))
        #expect(frame.width == 256 && frame.height == 256)
        #expect(frame.step == 4 && frame.steps == 9)
    }

    @Test("Every preview state names a surface")
    func everyStateOpensSomewhere() {
        #expect(MobilePreviewState.allCases.count == 9)
        #expect(MobilePreviewState.library.tab == .library)
        #expect(MobilePreviewState.viewer.tab == .library)
        #expect(MobilePreviewState.today.tab == .today)
        #expect(MobilePreviewState.settings.tab == .settings)
        #expect(MobilePreviewState.pairing.tab == .canvas)
        #expect(MobilePreviewState.capsule.tab == .canvas)
    }

    /// The one state the fixture cannot hold either: a run in flight with another behind it.
    /// Both carry batch identities of their own, since a list cannot hold one run twice.
    @Test("The Today state has one run going and one waiting, on top of the fixture's own")
    func todayHasARunAndAQueue() throws {
        let today = try #require(MobilePreview.todayRuns(MobilePreview.snapshot()))

        #expect(today.engine.kind == .generating)
        #expect(today.queue.count == 1)
        #expect(today.running != nil)
        #expect(today.today.filter { $0.state == .running }.count == 1)
        #expect(today.today.filter { $0.state == .waiting }.count == 1)
        #expect(today.today.filter { $0.state == .finished }.count == 2, "the fixture's own")
        #expect(Set(today.today.map(\.id)).count == today.today.count, "no run listed twice")
    }
}
