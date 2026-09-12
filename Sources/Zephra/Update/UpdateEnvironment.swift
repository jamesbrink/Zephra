import Foundation
import ZephraSnapshot

/// The two `ZEPHRA_*` switches the updater honours, read once at the composition root and
/// handed down as a value, the way `InferenceEnvironment` is.
///
/// - `ZEPHRA_UPDATE_FEED=<url>` points the check at another manifest, which is how the whole
///   path is exercised against `python3 -m http.server` instead of the assets bucket.
/// - `ZEPHRA_UPDATE_BUILD=<stamp>` makes this build claim to be an older one, so a published
///   release reads as newer without shipping a release first.
///
/// Both are Debug-only, for the reason `ZEPHRA_PREVIEW_STATE` is: a shipped, signed Zephra has
/// no business fetching its next version from wherever an environment variable happened to
/// point, and `current` answering the production feed in Release is what makes that true
/// without anything outside this file knowing the hooks exist.
struct UpdateEnvironment: Hashable, Sendable {
    static let feedVariable = "ZEPHRA_UPDATE_FEED"
    static let buildVariable = "ZEPHRA_UPDATE_BUILD"

    /// The manifest to read; the published one unless a Debug launch said otherwise.
    var feed: URL = UpdateFeed.production
    /// The build this launch claims to be, or nil to use the one stamped into the bundle.
    var pretendBuild: String?

    /// Whether this launch is a hand run against a feed of somebody's own. `UpdateEligibility`
    /// reads it: a Debug run out of `build/Debug` is exactly what the hand test drives, and
    /// refusing it for not being in `/Applications` would leave the whole path untestable.
    var isOverridden: Bool { feed != UpdateFeed.production || pretendBuild != nil }

    /// Reads both switches out of `environment`. Pure, so it is tested; a value that does not
    /// parse is ignored rather than fatal, the way every other hook's is.
    static func read(_ environment: [String: String]) -> UpdateEnvironment {
        var resolved = UpdateEnvironment()
        if let named = environment[feedVariable], let url = URL(string: named), url.scheme != nil {
            resolved.feed = url
        }
        if let stamp = environment[buildVariable], !stamp.isEmpty {
            resolved.pretendBuild = stamp
        }
        return resolved
    }

    /// What this launch runs under. `#if DEBUG` here rather than at the call site, so a Release
    /// build reads the production feed and its own build number whatever is set.
    static var current: UpdateEnvironment {
        #if DEBUG
        read(ProcessInfo.processInfo.environment)
        #else
        UpdateEnvironment()
        #endif
    }
}
