import Foundation
import Testing
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraLinkHost
@testable import ZephraEngine

/// What a phone is told by a Mac whose GPU has stopped running its work.
///
/// The Mac's own sentence, once, for every command that would reach the device: a phone told
/// "cannot load a model just now" reads a moment passing, and this is not a moment — nothing
/// this Mac is asked for will run again until it has been relaunched. What does not need the
/// GPU keeps working, because a folder is a folder whatever the driver is doing.
@MainActor
@Suite("A Mac that has lost the GPU, as a phone hears it")
struct CompanionDeviceLossTests {
    /// The Mac's store, brought up and then told the runtime's latch has closed — the way
    /// bender's did, inside an unload, with nothing throwing.
    static func lostBed() async throws -> CompanionTestBed {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        bed.engine.control.update { $0.deviceLost = true }
        bed.store.transition(to: .idle)
        #expect(bed.store.deviceLost)
        return bed
    }

    @Test("every command that would reach the device is refused in the Mac's own words")
    func theGPUCommandsAreRefused() async throws {
        let bed = try await Self.lostBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        for command in [
            Command.loadModel(bed.store.descriptor.id),
            .unloadModel,
            .switchModel(bed.store.descriptor.id),
            .upscale(name: "a-picture.png", factor: 2),
            .animate(name: "a-picture.png"),
        ] {
            let reply = try await phone.request(command)
            guard case .error(let error) = reply else {
                Issue.record("expected \(command) to be refused, got \(reply)")
                continue
            }
            #expect(error.code == .refused)
            #expect(error.reason == EngineError.deviceLost.message)
        }
        #expect(bed.engine.control.settings.unloads == 0, "and nothing was submitted for them")
        await bed.shutdown()
    }

    @Test("a strict offer and a strict submit are refused before any receipt exists")
    func multiHostWorkHearsTheSameSentence() async throws {
        let bed = try await Self.lostBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        // Ready in every other way, so the lost GPU is the only thing being tested: a refusal
        // here could otherwise have come from the model not being installed rather than from
        // the driver having stopped.
        let model = bed.store.descriptor
        bed.store.memoryBudget = MemoryBudget(physicalMemory: 1_000_000_000_000)
        bed.store.availability[model.id] = .available
        var settings = model.capabilities.clamp(bed.store.settings)
        settings.prompt = "a lighthouse at dusk"
        let job = StrictGeneration(
            request: GenerationRequest(modelID: model.id, count: 1, settings: settings))

        for command in [Command.multiHost(.offer(job)), .multiHost(.submit(job))] {
            let reply = try await phone.request(command)
            guard case .error(let error) = reply else {
                Issue.record("expected \(command) to be refused, got \(reply)")
                continue
            }
            #expect(error.code == .refused)
            #expect(error.reason == EngineError.deviceLost.message)
        }
        // The submit refused above is the whole point: past the ledger it would have written a
        // `.prepared` receipt and then had `enqueue` turn it away, leaving the phone holding a
        // receipt frozen at `unknown` beside the sentence it was told instead.
        #expect(bed.store.queue.isEmpty, "and no work reached the store")
        #expect(try bed.host.receipts.read(peer: phone.identity.publicKeys,
            request: job.request.requestID) == nil, "and no receipt was written for it")
        await bed.shutdown()
    }

    @Test("the repeat of an accepted submit reads its receipt rather than hearing a refusal")
    func aReplayedSubmitIsNeverAFalseRejection() async throws {
        let bed = CompanionTestBed()
        bed.engine.control.update { $0.stepDelay = .milliseconds(30) }
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        let model = bed.store.descriptor
        bed.store.memoryBudget = MemoryBudget(physicalMemory: 1_000_000_000_000)
        bed.store.availability[model.id] = .available
        var settings = model.capabilities.clamp(bed.store.settings)
        settings.prompt = "a lighthouse at dusk"
        let job = StrictGeneration(
            request: GenerationRequest(modelID: model.id, count: 2, settings: settings))

        guard case .multiHost(.receipt(let accepted)) = try await phone.request(.multiHost(.submit(job))) else {
            Issue.record("expected the first submit to be accepted")
            await bed.shutdown()
            return
        }
        #expect(accepted.status == .accepted)
        // The GPU goes after the work was taken, which is when a reply goes missing: the phone
        // asks again, and `LinkClient` repeats every command but `upscale`.
        bed.engine.control.update { $0.deviceLost = true }

        let again = try await phone.request(.multiHost(.submit(job)))

        guard case .multiHost(.receipt(let replayed)) = again else {
            Issue.record("a replayed submit must answer with its receipt, got \(again)")
            await bed.shutdown()
            return
        }
        // The phone marks a `LinkError` on a submission `.rejected` and never reconciles a
        // rejection, so a refusal here would have been a permanent record of a job this Mac did
        // take — named twice, once as accepted and once as refused.
        #expect(replayed.batchID == accepted.batchID)
        #expect(replayed.digest == accepted.digest)
        #expect(replayed.status == accepted.status)
        await bed.shutdown()
    }

    @Test("a generation is refused with the same sentence rather than a busy Mac's")
    func enqueueHearsTheSameSentence() async throws {
        let bed = try await Self.lostBed()
        let phone = try await bed.pairedPhone()
        let snapshot = try await phone.snapshot()
        var settings = GenerationSettings.defaults(for: bed.store.descriptor)
        settings.prompt = "a lighthouse"
        let request = GenerationRequest(
            modelID: bed.store.descriptor.id, count: 1, settings: settings)

        let reply = try await phone.request(.enqueue(request))

        guard case .error(let error) = reply else {
            Issue.record("expected a refusal, got \(reply)")
            return
        }
        #expect(error.code == .refused)
        #expect(error.reason == EngineError.deviceLost.message)
        #expect(bed.store.queue.isEmpty)
        #expect(!snapshot.engine.canQueue, "and the button was never lit in the first place")
        await bed.shutdown()
    }

    @Test("what does not need the GPU still answers")
    func theLibraryKeepsWorking() async throws {
        let bed = try await Self.lostBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        #expect(try await phone.request(.resync) == .ok)
        #expect(try await phone.request(.multiHost(.previews(false))) == .ok)
        await bed.shutdown()
    }
}
