import Foundation
import ZephraLinkProtocol

/// The capsule following the Mac's run, which is the Mac's own rule in a phone's shape.
///
/// On the Mac, Generate starts following the run and `watchRun()` puts the run's settings back
/// in the capsule (`GenerationStore+FollowingRun`). Here the run arrives as `snapshot.running`,
/// and the draft takes its settings so a phone picked up while the Mac is rendering shows what
/// the Mac is making rather than "Describe a picture". What stops it is the one thing a draft
/// holds that the Mac did not say: a prompt somebody typed here is never written over.
extension PromptDraft {
    /// Takes the run's model and settings as the next press's, while nothing typed here would
    /// be lost.
    ///
    /// The draft is untouched when its prompt is empty or is the last prompt it followed or
    /// sent, so a run the phone itself submitted is followed harmlessly and a later run of the
    /// Mac's replaces it. The well is emptied — the phone has no pixels for the Mac's pictures,
    /// since `QueuedEntry` strips them — while every origin the row carries stays, all N of
    /// them, because a name is not bytes: a run made from three pictures follows as three
    /// origins and the capsule can say so. The continuation goes with the well: on the Mac an
    /// empty well drops it, and the
    /// Mac's `clamp` would drop one with no frames anyway. Nothing to follow changes nothing,
    /// the way the Mac's capsule keeps a finished run's settings.
    func follow(_ running: QueuedEntry?) {
        guard let running, isUntouched else { return }
        clearReference()
        var followed = running.settings
        followed.continuation = nil
        settings = followed
        modelID = running.modelID
        followedPrompt = followed.prompt
    }

    /// Records that the request went to the Mac, so the run it becomes is followed rather than
    /// mistaken for something still being typed.
    func noteSubmitted(_ request: GenerationRequest) {
        followedPrompt = request.settings.prompt
    }

    /// Whether the prompt is nobody's: empty, or the last one followed or sent.
    private var isUntouched: Bool {
        settings.prompt.isEmpty || settings.prompt == followedPrompt
    }
}
