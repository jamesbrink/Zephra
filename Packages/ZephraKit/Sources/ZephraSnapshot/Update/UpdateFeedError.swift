import Foundation

/// Why reading `releases/latest.json` did not produce a release.
///
/// Three answers, because three different things are worth telling a person who pressed Check
/// for Updates: the host could not be reached at all, it answered and refused, or it answered
/// with something that is not a release. A check that nobody asked for says none of them; the
/// menu item is the one place these reach the screen.
public enum UpdateFeedError: Error, Hashable, Sendable {
    /// The request never got an answer: no network, a name that does not resolve, a timeout.
    case unreachable(reason: String)
    /// The host answered with a status that is not 200.
    case refused(status: Int)
    /// The bytes arrived and were not a release manifest.
    case malformed

    /// What to tell someone, without the jargon of the layer it came from.
    public var message: String {
        switch self {
        case .unreachable(let reason):
            "Zephra could not reach the update server: \(reason)"
        case .refused(let status):
            "The update server answered HTTP \(status)."
        case .malformed:
            "The update server answered with something this version of Zephra cannot read."
        }
    }
}
