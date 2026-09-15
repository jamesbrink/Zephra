import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraMobile

/// The two new keys against the fixture, which is a Mac from before either of them existed.
///
/// The bundled snapshot is deliberately left without them, so every frozen state but `failed`
/// reads as an older Mac and the fallback is exercised on every build. `failed` is the one state
/// that raises them, and it goes back through the wire's own coder here rather than being
/// trusted as a Swift value: a fixture is only a fixture while it still decodes as what a Mac
/// would send.
@Suite("The loading keys against a Mac that never had them")
struct ModelLoadingFixtureTests {
    @Test("The fixture carries neither key, and reads as what that Mac meant")
    func theFixtureIsAnOlderMac() throws {
        let snapshot = try #require(MobilePreview.snapshot())
        #expect(snapshot.modelLoading == nil, "so the phone offers that Mac neither command")
        #expect(snapshot.engine.kind == .ready)
        #expect(
            snapshot.engine.loadedModelID == snapshot.engine.modelID,
            "every kind but idle meant the chosen model was in play")
    }

    @Test("A new Mac holding nothing is told apart from a Mac that never said")
    func nothingLoadedIsToldFromNothingSaid() throws {
        var snapshot = try #require(MobilePreview.snapshot())
        snapshot.engine = EngineStateDTO(
            kind: .ready, modelID: snapshot.model.id, loadedModelID: nil, acceptsGeneration: true)
        let data = try LinkJSON.encode(snapshot)
        let newer = try LinkJSON.decode(StateSnapshot.self, from: data)
        #expect(
            newer.engine.loadedModelID == nil,
            "the key is written null rather than omitted, so ready-with-nothing-in survives")

        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var engine = try #require(json["engine"] as? [String: Any])
        #expect(engine.keys.contains("loadedModelID"))
        engine.removeValue(forKey: "loadedModelID")
        json["engine"] = engine
        let older = try LinkJSON.decode(
            StateSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(
            older.engine.loadedModelID == snapshot.model.id,
            "and the same bytes without the key are the older Mac's own meaning")
    }

    @Test("The lost-run state raises both keys, and survives the wire")
    func theLostRunStateCrossesWhole() throws {
        let shaped = MobilePreview.lostRun(try #require(MobilePreview.snapshot()))
        let crossed = try LinkJSON.decode(StateSnapshot.self, from: LinkJSON.encode(shaped))
        #expect(crossed.modelLoading == true)
        #expect(crossed.engine.kind == .failed)
        #expect(crossed.engine.loadedModelID == nil, "a fault leaves the chosen model unloaded")
        #expect(crossed.engine.modelID == crossed.model.id)
        #expect(crossed.engine.canQueue, "the Mac would load it behind the press")
        #expect(crossed.engine.message?.isEmpty == false)
    }
}
