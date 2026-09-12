import Foundation
import Testing
import ZephraCore
import ZephraLinkProtocol

@testable import ZephraMobile

/// What a press of Generate sends, which is where the seed rule lives: a fresh seed for every
/// press unless somebody locked the one on screen.
@MainActor
@Suite("Every press picks its own seed, unless the seed is locked")
struct PromptDraftSubmissionTests {
    /// A plain picture model, since nothing here is about a model's bounds.
    private var model: CapabilitiesSummary {
        CapabilitiesSummary(
            ModelCapabilities(
                sizeAlignment: 64,
                sizePresets: [ImageSize(width: 1024, height: 1024)],
                sizeBounds: 256...2048,
                defaultSize: ImageSize(width: 1024, height: 1024),
                stepBounds: 1...20, defaultSteps: 9,
                guidanceBounds: 0...0, defaultGuidance: 0,
                supportsNegativePrompt: false, supportsSeed: true,
                supportsReferenceImage: false,
                referenceStrengthBounds: 1...1, defaultReferenceStrength: 1))
    }

    private func draft(seed: UInt64) -> PromptDraft {
        let draft = PromptDraft()
        draft.settings.prompt = "a red bicycle"
        draft.settings.seed = seed
        return draft
    }

    @Test("Two presses send two seeds")
    func twoPressesSendTwoSeeds() {
        let draft = draft(seed: 7)
        let first = draft.submission(clampedBy: model, randomizingSeed: true)
        let second = draft.submission(clampedBy: model, randomizingSeed: true)
        #expect(first.settings.seed != 7, "the seed the draft was sitting on is not sent again")
        #expect(first.settings.seed != second.settings.seed)
    }

    @Test("The capsule shows the seed that went, not the one before it")
    func theCapsuleShowsWhatWasSent() {
        let draft = draft(seed: 7)
        let request = draft.submission(clampedBy: model, randomizingSeed: true)
        #expect(draft.settings.seed == request.settings.seed)
    }

    @Test("With the seed kept, two presses send one seed")
    func aLockedSeedIsRepeated() {
        let draft = draft(seed: 7)
        let first = draft.submission(clampedBy: model, randomizingSeed: false)
        let second = draft.submission(clampedBy: model, randomizingSeed: false)
        #expect(first.settings.seed == 7)
        #expect(second.settings.seed == 7)
        #expect(draft.settings.seed == 7)
    }

    @Test("The fresh seed is the one the Mac's own clamp saw")
    func randomisingPrecedesTheClamp() {
        let draft = draft(seed: 7)
        // Steps out of bounds, so the request is one the clamp really rewrote: the seed it
        // carries is therefore the seed that was in the settings when the clamp ran, which is
        // the fresh one rather than the one the draft started on.
        draft.settings.steps = 99
        let request = draft.submission(clampedBy: model, randomizingSeed: true)
        #expect(request.settings.steps == 20)
        #expect(request.settings.seed == draft.settings.seed)
        #expect(request.settings.seed != 7)
    }

    @Test("The lock says which way it is about to go")
    func theLockSaysWhatItWillDo() {
        #expect(SeedLockToggle.hint(randomizing: true).contains("new seed"))
        #expect(SeedLockToggle.hint(randomizing: false).contains("Keeping this seed"))
        #expect(
            SeedLockToggle.hint(randomizing: true) != SeedLockToggle.hint(randomizing: false))
    }
}
