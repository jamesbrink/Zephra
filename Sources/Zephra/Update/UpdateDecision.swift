import Foundation
import ZephraEngine

/// The two questions the banner asks, answered as pure functions over the state rather than as
/// conditions spread across a view: may the update be installed right now, and is the banner
/// worth drawing at all.
enum UpdateDecision {
    /// Why Update Now is greyed out, or nil when it may be pressed.
    ///
    /// Installing quits the app, so the only thing that blocks it is work that would be thrown
    /// away or left half-done: a transfer, a build, a run, an upscale, or a stop being
    /// honoured. Loading weights and warming up are deliberately not on the list — they are
    /// seconds, and `AppLifecycle` already defers the quit until `GenerationStore.shutdown`
    /// settles, which is the same guarantee Quit itself gives.
    static func installBlockedReason(engine: EngineState, hasActiveDownloads: Bool) -> String? {
        switch engine {
        case .downloading: return "Zephra is downloading a model."
        case .building: return "Zephra is building a model."
        case .generating: return "Zephra is making an image."
        case .upscaling: return "Zephra is making an image larger."
        case .cancelling: return "Zephra is finishing what it was doing."
        case .idle, .checkingModel, .loading, .warmingUp, .ready, .failed: break
        }
        return hasActiveDownloads ? "Zephra is downloading a model." : nil
    }

    /// Whether the banner belongs on screen.
    ///
    /// A release the person pressed Later on is snoozed for the session and not for longer:
    /// with no version bumps, a skip written to disk would be a skip of every build after it,
    /// and the one thing worse than a banner is a Mac that silently stops updating. Everything
    /// that is not `idle` — a check in flight aside — is on screen, since a download, an
    /// install and a failure all belong where the press that started them was.
    static func showsBanner(phase: UpdatePhase, snoozedBuild: String?) -> Bool {
        switch phase {
        case .idle, .checking:
            return false
        case .failed:
            return true
        case .available, .downloading, .ready, .installing:
            guard let build = phase.release?.build else { return true }
            return build != snoozedBuild
        }
    }
}
