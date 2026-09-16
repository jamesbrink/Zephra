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
        // A Mac with nothing loaded takes a generation now and loads what the entry needs, so
        // the refusal this is about is a model that is not on the disk to be loaded at all.
        bed.engine.control.update {
            $0.availability[ModelCatalog.default.id] = .missing(reason: "never built")
        }
        await bed.store.refreshAvailability()
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

    @Test("a phone can tell the Mac to read a model in and to give it back")
    func loadAndUnloadFromThePhone() async throws {
        let bed = CompanionTestBed()
        bed.store.warmsUpAfterLoad = false
        bed.store.loadingMode = .onDemand
        await bed.store.bootstrap()
        #expect(bed.store.loadedDescriptor == nil, "an on-demand launch loads nothing")
        let phone = try await bed.pairedPhone()
        let world = try await phone.snapshot()
        #expect(world.modelLoading == true, "the Mac says it understands the two commands")
        #expect(world.engine.loadedModelID == nil, "and that it is holding nothing")

        #expect(try await phone.request(.loadModel(ModelCatalog.default.id)) == .ok)
        try await bed.waitUntil { bed.store.state == .ready }
        await bed.store.settle()
        #expect(bed.store.loadedDescriptor?.id == ModelCatalog.default.id)
        #expect(
            EngineStateProjection.engine(bed.store).loadedModelID == ModelCatalog.default.id,
            "which the next state update says")

        #expect(try await phone.request(.unloadModel) == .ok)
        try await bed.waitUntil { bed.store.loadedDescriptor == nil }
        await bed.store.settle()
        #expect(bed.store.descriptor.id == ModelCatalog.default.id, "the choice survives")
        #expect(EngineStateProjection.engine(bed.store).loadedModelID == nil)
        await bed.shutdown()
    }

    @Test("a load the Mac will not start is refused, and does not move the chosen model")
    func loadTheMacWillNotStartIsRefused() async throws {
        let bed = CompanionTestBed()
        bed.engine.control.update { $0.stepDelay = .milliseconds(20) }
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        bed.store.settings.prompt = "a lighthouse"
        bed.store.settings.steps = 8
        bed.store.generate()
        try await bed.engine.waitForStep()
        let chosen = bed.store.descriptor.id

        let reply = try await phone.request(.loadModel(ModelCatalog.zImageTurbo4bit.id))

        guard case .error(let error) = reply else {
            Issue.record("expected a refusal, got \(reply)")
            await bed.shutdown()
            return
        }
        #expect(error.code == .busy)
        // The heart of it: `loadModel()` returns silently when it will not load, so switching
        // first would move the chosen model and clamp the settings under the person at the
        // keyboard while the phone was told the load succeeded.
        #expect(bed.store.descriptor.id == chosen, "the capsule is the person's, not the phone's")

        bed.store.cancel()
        try await bed.engine.waitUntil { !bed.store.isDraining && bed.store.queue.isEmpty }
        await bed.shutdown()
    }

    @Test("a load of a model that is not on the disk is refused rather than answered ok")
    func loadOfAMissingModelIsRefused() async throws {
        let bed = CompanionTestBed()
        bed.engine.control.update {
            $0.availability[ModelCatalog.zImageTurbo4bit.id] = .missing(reason: "never built")
        }
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        let chosen = bed.store.descriptor.id

        let reply = try await phone.request(.loadModel(ModelCatalog.zImageTurbo4bit.id))

        guard case .error(let error) = reply else {
            Issue.record("expected a refusal, got \(reply)")
            await bed.shutdown()
            return
        }
        #expect(error.code == .busy)
        #expect(bed.store.descriptor.id == chosen)
        await bed.shutdown()
    }

    @Test("an unload asked for twice is answered twice, since a lost reply is asked again")
    func unloadIsAnsweredWhateverHasAlreadyHappened() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        #expect(try await phone.request(.unloadModel) == .ok)
        // The reply went missing, so the phone asks again under a fresh id — which `request`
        // does by itself for a repeatable command. The first ask is still settling, so a Mac
        // that read `canUnload` here would answer "cannot unload" over the unload it is doing.
        #expect(try await phone.request(.unloadModel) == .ok)
        try await bed.waitUntil { bed.store.loadedDescriptor == nil }
        await bed.store.settle()
        #expect(try await phone.request(.unloadModel) == .ok, "and again once it has settled")
        #expect(bed.engine.control.settings.unloads == 1, "one unload, however often asked")
        await bed.shutdown()
    }

    @Test("a load of a model this Mac cannot hold is refused in the words its greyed row carries")
    func loadingAnUnholdableModelIsRefused() async throws {
        let bed = CompanionTestBed()
        bed.store.memoryBudget = MemoryGuardStoreTests.straddling
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let reply = try await phone.request(
            .loadModel(MemoryGuardStoreTests.tooLarge.id))

        guard case .error(let error) = reply else {
            Issue.record("expected a refusal, got \(reply)")
            await bed.shutdown()
            return
        }
        #expect(error.reason.hasPrefix("\(MemoryGuardStoreTests.tooLarge.fullName) needs"))
        #expect(bed.store.descriptor.id != MemoryGuardStoreTests.tooLarge.id)
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

    @Test("a request the phone sends twice queues one run, not two")
    func aRepeatedEnqueueQueuesOnce() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        // The same request twice, which is what a phone does when the reply to the first went
        // missing: a fresh envelope around the press of Generate it is still holding.
        let request = Self.request()
        let first = try await phone.request(.enqueue(request))
        let again = try await phone.request(.enqueue(request))

        guard case .queued(let batch) = first, case .queued(let repeated) = again else {
            Issue.record("expected two run ids, got \(first) and \(again)")
            return
        }
        #expect(batch == repeated, "the same press, answered with the run it already made")
        try await bed.waitUntil { !bed.store.history.isEmpty }
        try await Task.sleep(for: .milliseconds(100))
        #expect(bed.store.history.count == 1, "one run, however many times it was asked for")
        #expect(bed.store.queue.isEmpty)
        await bed.shutdown()
    }

    @Test("a phone that stepped over a hole is answered, and then sent the world again")
    func resyncSendsTheWholeStateAgain() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let reply = try await phone.request(.resync)

        #expect(reply == .ok)
        let snapshot = try await phone.waitFor { () -> Envelope? in
            let snapshots = phone.envelopes.filter { $0.kind == .snapshot }
            return snapshots.count == 2 ? snapshots.last : nil
        }
        #expect(try snapshot.decode(StateSnapshot.self).hostName == "A Test Mac")
        #expect(
            phone.envelopes.firstIndex { $0.kind == .reply }
                .map { $0 < (phone.envelopes.lastIndex { $0.kind == .snapshot } ?? 0) } == true,
            "the ok closes the request before the state it asked for arrives")
        #expect(bed.host.sessions.count == 1, "and the session carries on")
        await bed.shutdown()
    }
}
