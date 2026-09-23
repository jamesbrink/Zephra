import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraMobile

@Suite("The line under Generate follows the run the press queued")
struct RunFollowingTests {
    let batch = UUID()

    /// The bundled Mac, idle, with nothing queued or running and no runs today.
    func mac(_ edit: (inout StateSnapshot) -> Void = { _ in }) throws -> StateSnapshot {
        var snapshot = try #require(MobilePreview.snapshot())
        snapshot.queue = []
        snapshot.running = nil
        snapshot.today = []
        snapshot.engine = EngineStateDTO(kind: .ready, acceptsGeneration: true)
        edit(&snapshot)
        return snapshot
    }

    func entry() -> QueuedEntry {
        QueuedEntry(id: UUID(), batchID: batch, batchIndex: 0, modelID: "m",
            settings: PromptDraft().settings)
    }

    func run(_ state: RunSummary.State) -> RunSummary {
        RunSummary(id: batch, prompt: "p", modelID: "m", width: 8, height: 8, state: state,
            fileNames: [], seedCount: 1, startedAt: nil, finishedAt: nil)
    }

    @Test("an accepted run says it is queued before the Mac has said so")
    func queuedBeforeTheDelta() throws {
        var following = RunFollowing(batchID: batch, hostName: "Halcyon")
        following.read(try mac())
        #expect(following.note == "Queued on Halcyon")
    }

    @Test("a run being rendered says the Mac's own phase")
    func runningSaysThePhase() throws {
        var following = RunFollowing(batchID: batch, hostName: "Halcyon")
        following.read(try mac { $0.queue = [entry()] })
        #expect(following.note == "Queued on Halcyon")
        following.read(try mac {
            $0.running = entry()
            $0.engine = EngineStateDTO(kind: .generating, phase: "Denoising", isBusy: true)
        })
        #expect(following.note == "Denoising on Halcyon")
    }

    @Test("a finished run clears the line")
    func finishedClears() throws {
        var following = RunFollowing(batchID: batch, hostName: "Halcyon")
        following.read(try mac { $0.running = entry() })
        following.read(try mac { $0.today = [run(.finished)] })
        #expect(following.note == nil)
        following.read(try mac { $0.queue = [entry()] })
        #expect(following.hasEnded)
    }

    @Test("a run finished while the phone was away clears on the first snapshot back")
    func finishedUnseen() throws {
        var following = RunFollowing(batchID: batch, hostName: "Halcyon")
        following.read(try mac { $0.today = [run(.finished)] })
        #expect(following.hasEnded)
    }

    @Test("a run that was seen and is named nowhere any more has ended")
    func stoppedClears() throws {
        var following = RunFollowing(batchID: batch, hostName: "Halcyon")
        following.read(try mac { $0.queue = [entry()] })
        following.read(try mac())
        #expect(following.hasEnded)
    }

    @Test("a failure the phone watched happen clears the line")
    func failureClears() throws {
        var following = RunFollowing(batchID: batch, hostName: "Halcyon")
        following.read(try mac { $0.engine = EngineStateDTO(kind: .loading, isBusy: true) })
        following.read(try mac { $0.engine = EngineStateDTO(kind: .failed, message: "No.") })
        #expect(following.hasEnded)
    }

    @Test("an earlier failure still on the Mac does not end a run it just accepted")
    func earlierFailureStands() throws {
        var following = RunFollowing(batchID: batch, hostName: "Halcyon")
        following.read(try mac { $0.engine = EngineStateDTO(kind: .failed, message: "Old.") })
        #expect(following.note == "Queued on Halcyon")
    }
}
