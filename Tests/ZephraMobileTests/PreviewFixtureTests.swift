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
        #expect(!running.acceptsWork)
    }

    @Test("Every preview state names a surface")
    func everyStateOpensSomewhere() {
        #expect(MobilePreviewState.allCases.count == 6)
        #expect(MobilePreviewState.library.tab == .library)
        #expect(MobilePreviewState.settings.tab == .settings)
        #expect(MobilePreviewState.pairing.tab == .canvas)
    }
}
