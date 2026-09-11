import Foundation
import Testing
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// A phone connecting to a Mac: who is let in, what they are told first, and what a request
/// from one does to the Mac it lands on.
@MainActor
@Suite("A paired phone talks to the Mac over the link")
struct CompanionHostTests {
    /// What a phone would send: a prompt of its own, a couple of steps so the mock is quick.
    static func request(prompt: String = "a lantern on a jetty at dusk") -> GenerationRequest {
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = prompt
        settings.steps = 2
        settings.size = ImageSize(width: 512, height: 512)
        return GenerationRequest(modelID: ModelCatalog.default.id, count: 1, settings: settings)
    }

    @Test("pairing through a session stores the device and takes the code down")
    func pairingStoresTheDevice() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone(named: "James's iPhone")
        _ = try await phone.snapshot()

        #expect(bed.host.devices.map(\.name) == ["James's iPhone"])
        #expect(bed.host.devices.first?.keys == phone.identity.publicKeys)
        #expect(bed.host.pairing == nil, "one code pairs one phone")
        #expect(try bed.pairings.load().count == 1, "and it survives a relaunch")
        await bed.shutdown()
    }

    @Test("a device that has paired comes back without a code, and a stranger is refused")
    func reconnectionNeedsNoCode() async throws {
        let bed = CompanionTestBed()
        let identity = DeviceIdentity()
        let first = try await bed.pairedPhone(identity: identity)
        _ = try await first.snapshot()
        await first.disconnect()

        let again = try await bed.phone(identity: identity)
        #expect(try await again.snapshot().hostName == "A Test Mac")

        let (_, failure) = await bed.refusedPhone()
        #expect((failure as? LinkError)?.code == .notPaired)
        #expect(bed.host.devices.count == 1, "a refusal pairs nothing")
        await bed.shutdown()
    }

    @Test("the first sealed message is a snapshot of the Mac as it stands")
    func snapshotComesFirst() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        let snapshot = try await phone.snapshot()

        #expect(
            phone.envelopes.first { $0.kind != .accept }?.kind == .snapshot,
            "nothing precedes it once the handshake is done")
        #expect(snapshot.engine.kind == .ready)
        #expect(snapshot.engine.acceptsGeneration)
        #expect(snapshot.model.id == bed.store.descriptor.id)
        #expect(snapshot.models.count == ModelCatalog.all.count)
        #expect(snapshot.acceptsWork)
        await bed.shutdown()
    }

    @Test("nothing is published twice: a fresh session gets no delta repeating its snapshot")
    func openingPublishesNothingTwice() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        try await Task.sleep(for: .milliseconds(150))

        #expect(try phone.deltas().isEmpty, "the snapshot was already the whole state")
        await bed.shutdown()
    }

    @Test("a submit from the phone queues without touching the capsule, and lands in history")
    func submitLeavesTheCapsuleAlone() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        bed.store.settings.prompt = "what the person at the Mac is typing"
        let typed = bed.store.settings
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let reply = try await phone.request(.enqueue(Self.request()))

        guard case .queued = reply else {
            Issue.record("expected a run id, got \(reply)")
            return
        }
        #expect(bed.store.settings == typed, "the prompt being written is not the phone's")
        #expect(!bed.store.followsRun, "a remote run never takes the canvas")
        try await bed.waitUntil { !bed.store.history.isEmpty }
        let inserted = try await phone.waitFor {
            (try? phone.deltas())?.compactMap { delta -> HistoryEntry? in
                guard case .historyInserted(let entry) = delta else { return nil }
                return entry
            }.first
        }
        #expect(inserted.record.prompt == "a lantern on a jetty at dusk")
        await bed.shutdown()
    }

    @Test("the picture's file name reaches the phone once the write lands")
    func historyRowIsSentAgainWhenItsFileNameArrives() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        var state = try await phone.snapshot()

        // The two halves of a save, apart, because that is what the bug was: a picture enters
        // history with no file name and is given one when the write lands, and the second half
        // changes the row without changing the list of ids.
        var image = GeneratedImage(
            pngData: Data([0x89, 0x50]), settings: Self.request().settings,
            modelID: ModelCatalog.default.id, duration: .seconds(1))
        bed.store.history = [image]
        bed.host.publishNow()
        let first = try await phone.waitFor { () -> HistoryEntry? in
            for delta in (try? phone.deltas()) ?? [] { state = state.applying(delta) }
            return state.history.first
        }
        #expect(first.fileName == nil, "nothing is written yet")

        image = image.withFileURL(URL(filePath: "/tmp/zephra-test-lantern.png"))
        bed.store.history = [image]
        bed.host.publishNow()

        let named = try await phone.waitFor { () -> String? in
            for delta in (try? phone.deltas()) ?? [] { state = state.applying(delta) }
            return state.history.first?.fileName
        }
        #expect(named == "zephra-test-lantern.png", "the phone has nothing to fetch without it")
        await bed.shutdown()
    }

    @Test("a submit the Mac will not take comes back with the reason it gave")
    func refusedSubmitCarriesTheReason() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let reply = try await phone.request(.enqueue(Self.request()))

        guard case .error(let error) = reply else {
            Issue.record("expected a refusal, got \(reply)")
            return
        }
        #expect(error.code == .refused)
        #expect(error.reason == "No model is loaded yet.", "the store's own words")
        #expect(bed.store.queue.isEmpty)
        await bed.shutdown()
    }

    @Test("a model this build does not ship is not found rather than refused")
    func unknownModelIsNotFound() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let reply = try await phone.request(.switchModel("not-in-the-catalog"))

        guard case .error(let error) = reply else {
            Issue.record("expected a refusal, got \(reply)")
            return
        }
        #expect(error.code == .notFound)
        await bed.shutdown()
    }

    @Test("revoking a device closes what it was doing, and says why")
    func revokingClosesTheSession() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        let device = try #require(bed.host.devices.first)

        await bed.host.revoke(device)

        let refusal = try await phone.waitFor { (try? phone.errors())?.first }
        #expect(refusal.code == .revoked)
        #expect(bed.host.devices.isEmpty)
        #expect(bed.host.sessions.isEmpty)
        await bed.shutdown()
    }
}
