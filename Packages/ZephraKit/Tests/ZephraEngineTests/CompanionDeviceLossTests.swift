import Foundation
import Testing
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

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
        var settings = GenerationSettings.defaults(for: bed.store.descriptor)
        settings.prompt = "a lighthouse at dusk"
        let job = StrictGeneration(
            request: GenerationRequest(
                modelID: bed.store.descriptor.id, count: 1, settings: settings))

        for command in [Command.multiHost(.offer(job)), .multiHost(.submit(job))] {
            let reply = try await phone.request(command)
            guard case .error(let error) = reply else {
                Issue.record("expected \(command) to be refused, got \(reply)")
                continue
            }
            #expect(error.code == .refused)
            #expect(error.reason == EngineError.deviceLost.message)
        }
        // The submit refused here is the whole point: past this line it would have written a
        // `.prepared` receipt before the store turned it away, and the phone would hold a
        // receipt frozen at `unknown` beside a refusal it was never given.
        #expect(bed.store.queue.isEmpty, "and no work reached the store")
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
