import Foundation
import ZephraLinkProtocol

/// What the Generate button may do right now, worked out once from what the Mac last said.
///
/// A value rather than three computed properties on the view, so the rules are read in a test
/// as sentences instead of looked at in a screenshot. Nothing here is a rule of the phone's:
/// `canQueue` and `acceptsWork` are the Mac's own answers, stamped into the state it sends, so
/// the button and the Mac that would refuse the press cannot disagree about a press.
struct GenerateAvailability: Equatable, Sendable {
    /// Whether a press would be taken.
    let isEnabled: Bool
    /// Whether Stop is worth offering beside it, which is exactly while a run is in flight.
    let showsStop: Bool
    /// How many generations are waiting behind the one being rendered, as a line under the
    /// button, or nil where nothing is waiting.
    let queueNote: String?

    /// Reads the three answers off the Mac's state.
    ///
    /// Generate never becomes Stop. A Mac rendering a picture will queue another behind it, as
    /// the Mac's own Generate does, so the press stays available and Stop appears beside it
    /// rather than in its place — which also means the button never moves under a thumb that
    /// was already on its way down.
    init(snapshot: StateSnapshot?, isLive: Bool, hasPrompt: Bool) {
        let engine = snapshot?.engine
        isEnabled =
            isLive && snapshot?.acceptsWork == true && engine?.canQueue == true && hasPrompt
        showsStop = engine?.kind == .generating
        let waiting = snapshot?.queue.count ?? 0
        queueNote = waiting > 0 ? "\(waiting) waiting" : nil
    }
}
