import Foundation
import Testing
import ZephraCore
import ZephraLinkProtocol

@testable import ZephraMobile

/// What the Generate button may do, as four sentences about a Mac.
///
/// The rules are the Mac's own, read off the state it sends: a press is taken when the session
/// is live, the Mac takes work at all, the engine would queue one, and there is a prompt to
/// queue. Nothing here is recomputed from the engine's case, which is the whole point — two
/// copies of a rule can disagree, and the one that greys out a button is the one nobody can
/// argue with.
@Suite("What the phone's Generate button may do")
struct GenerateAvailabilityTests {
    @Test("An idle Mac takes a press, and says nothing under the button")
    func anIdleMacTakesAPress() {
        let availability = Self.availability(
            EngineStateDTO(kind: .ready, acceptsGeneration: true, canQueue: true))
        #expect(availability.isEnabled)
        #expect(!availability.showsStop)
        #expect(availability.queueNote == nil)
    }

    @Test("A Mac rendering a picture takes a press too, and offers Stop beside it")
    func aRenderingMacTakesAPress() {
        let availability = Self.availability(Self.rendering, queue: 0)
        #expect(availability.isEnabled, "Generate queues behind the picture, as it does on the Mac")
        #expect(availability.showsStop, "Stop sits beside it rather than in place of it")
    }

    @Test("What is waiting is the line under the button")
    func whatIsWaitingIsSaid() {
        #expect(Self.availability(Self.rendering, queue: 1).queueNote == "1 waiting")
        #expect(Self.availability(Self.rendering, queue: 4).queueNote == "4 waiting")
    }

    @Test("An upscale, a load or no Mac at all takes no press")
    func everyWayAPressIsRefused() {
        let upscaling = EngineStateDTO(kind: .upscaling, isBusy: true)
        #expect(!Self.availability(upscaling).isEnabled, "an upscale is not a queue")
        #expect(!Self.availability(upscaling).showsStop, "and Stop here would stop nothing")

        let ready = EngineStateDTO(kind: .ready, acceptsGeneration: true, canQueue: true)
        #expect(!Self.availability(ready, isLive: false).isEnabled, "nothing to ask")
        #expect(!Self.availability(ready, acceptsWork: false).isEnabled, "a folder being moved")
        #expect(!Self.availability(ready, hasPrompt: false).isEnabled, "nothing to make")
        #expect(
            !GenerateAvailability(snapshot: nil, isLive: true, hasPrompt: true).isEnabled,
            "and a Mac that has said nothing yet")
    }

    @Test("A press in the air says nothing until the Mac answers it")
    func aPressInTheAir() {
        #expect(GeneratePress.idle.note == nil)
        #expect(GeneratePress.sending.isSending)
        #expect(GeneratePress.sending.note == nil)
        #expect(GeneratePress.refused("Zephra is quitting.").note == "Zephra is quitting.")
        #expect(!GeneratePress.refused("Zephra is quitting.").isSending)
    }

    /// A Mac four steps into a run.
    static let rendering = EngineStateDTO(
        kind: .generating, phase: "Denoising", step: 4, steps: 9, isBusy: true,
        acceptsGeneration: false, canQueue: true)

    /// One reading, over the bundle's own fixture with the engine and the queue swapped in —
    /// a Mac's real JSON rather than a literal, for `LibraryFixtures`' reason.
    static func availability(
        _ engine: EngineStateDTO,
        queue: Int = 0,
        isLive: Bool = true,
        acceptsWork: Bool = true,
        hasPrompt: Bool = true
    ) -> GenerateAvailability {
        guard var snapshot = MobilePreview.snapshot() else {
            fatalError("the preview snapshot fixture is missing from the test host's bundle")
        }
        snapshot.engine = engine
        snapshot.acceptsWork = acceptsWork
        snapshot.queue = (0..<queue).map { index in
            QueuedEntry(
                id: UUID(), batchID: Self.batch, batchIndex: index, modelID: snapshot.model.id,
                settings: GenerationSettings(
                    prompt: "a lighthouse in fog", size: ImageSize(width: 1024, height: 1024),
                    steps: 9, guidance: 0, seed: UInt64(index) + 1))
        }
        return GenerateAvailability(snapshot: snapshot, isLive: isLive, hasPrompt: hasPrompt)
    }

    private static let batch = UUID(uuidString: "6E0B3F27-51A4-4C9D-8B32-A7F014D25C86")!
}
