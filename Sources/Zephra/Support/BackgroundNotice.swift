import Foundation
import ZephraCore
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
    /// A picture or a clip on the disk, named by the prompt that made it: the file name is a
    /// stamp and a seed, which says nothing to the person who walked away from the window.
    ///
    /// The file name is carried all the same, unsaid, because it is what a click on the banner
    /// needs: this is the one notice that is about a thing rather than about the window, and
    /// `NoticeDestination` is how it travels to the other side of the notification centre.
    case imageSaved(prompt: String, isClip: Bool, fileName: String)
    case downloadFinished(model: String)
    case downloadFailed(model: String, reason: String)
    /// A newer Zephra has been published. Nothing has been fetched; the banner in the window
    /// is where it is installed from, and this is only what says the banner is there.
    case updateAvailable(version: String, build: String)

    /// The notice a picture written to `url` is worth, given the session's own record of it.
    ///
    /// A pure function rather than three expressions at the call site, because the file name
    /// it takes off the URL is the whole of what a click on the banner then finds again. An
    /// image the session's history has already let go is named only as saved.
    static func saved(at url: URL, image: GeneratedImage?) -> BackgroundNotice {
        .imageSaved(
            prompt: image?.settings.prompt ?? "",
            isClip: image?.isVideo ?? false,
            fileName: url.lastPathComponent)
    }

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
        case .imageSaved(_, let isClip, _): isClip ? "Clip Saved" : "Image Saved"
        case .downloadFinished: "Download Finished"
        case .downloadFailed: "Download Failed"
        case .updateAvailable: "Update Available"
        }
    }

    var body: String {
        switch self {
        case .imageSaved(let prompt, _, _): Self.summary(of: prompt)
        case .downloadFinished(let model): "\(model) is ready to load."
        case .downloadFailed(let model, let reason): "\(model): \(reason)"
        case .updateAvailable(let version, let build):
            "Zephra \(version) (build \(build)) is ready to install."
        }
    }

    /// How long a prompt the banner carries before it is cut, at a word.
    static let summaryLength = 100

    /// The prompt as one line for a banner: its line breaks and runs of spaces folded to one
    /// space, cut at the last word that fits with an ellipsis after it, and a word for an
    /// empty one, since a banner with no body reads as broken.
    static func summary(of prompt: String) -> String {
        let folded = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !folded.isEmpty else { return "Saved to your library." }
        guard folded.count > summaryLength else { return folded }
        let cut = folded.prefix(summaryLength)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord + "…"
    }
}
