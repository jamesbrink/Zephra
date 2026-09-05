import Foundation
import ZephraEngine

/// Something worth a notification when it happens while Zephra is not the front app: a
/// picture that has landed on the disk, or a download that has finished or given up. A run is
/// tens of seconds and a download is hours, and both are what a person walks away from.
///
/// Which engine transitions count is decided here, as a pure function over two states, so it
/// is tested rather than read off a switch in a view. A download that ends in a build, a load
/// or a ready model finished; one that ends in a failure failed; one that was stopped or
/// paused ends in neither and says nothing, because the person did that themselves.
enum BackgroundNotice: Equatable {
    case imageSaved(URL)
    case downloadFinished(model: String)
    case downloadFailed(model: String, reason: String)

    /// The notice a change from `old` to `new` is worth, or nil when it is worth none.
    static func transition(from old: EngineState, to new: EngineState, model: String) -> BackgroundNotice? {
        guard case .downloading = old else { return nil }
        switch new {
        case .building, .loading, .warmingUp, .ready:
            return .downloadFinished(model: model)
        case .failed(let error):
            return .downloadFailed(model: model, reason: error.message)
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .imageSaved: "Image Saved"
        case .downloadFinished: "Download Finished"
        case .downloadFailed: "Download Failed"
        }
    }

    var body: String {
        switch self {
        case .imageSaved(let url): url.deletingPathExtension().lastPathComponent
        case .downloadFinished(let model): "\(model) is ready to load."
        case .downloadFailed(let model, let reason): "\(model): \(reason)"
        }
    }
}
