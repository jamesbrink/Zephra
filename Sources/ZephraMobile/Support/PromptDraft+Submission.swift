import ZephraCore
import ZephraLinkProtocol

/// The press itself, which is the one moment a seed may change without anybody asking.
///
/// The Mac picks a fresh seed in `generateFromInterface`, under the same preference and in the
/// same place: before the request is built, never inside the engine. `GenerationStore.enqueue`
/// — the door a phone's request comes through — deliberately randomises nothing, because a
/// request that crossed the link is a request somebody already composed; so the phone does its
/// own randomising here, exactly where the Mac's own interface does.
extension PromptDraft {
    /// The request this press sends, with a fresh seed first where the preference asks for one.
    ///
    /// The seed is written back into the draft rather than only into the request, so the
    /// capsule shows the seed that went: a chip still showing the last run's seed is a chip
    /// that is lying about the picture being made. Randomising precedes the clamp for the same
    /// reason it does on the Mac — the clamp is what the model will actually run, and it must
    /// see the seed that was chosen.
    func submission(clampedBy summary: CapabilitiesSummary, randomizingSeed: Bool)
        -> GenerationRequest
    {
        if randomizingSeed { settings = settings.withRandomSeed() }
        return request(clampedBy: summary)
    }
}
