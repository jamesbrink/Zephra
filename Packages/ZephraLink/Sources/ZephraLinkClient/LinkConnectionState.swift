import Foundation

/// Where the phone's connection to its Mac has got to.
///
/// One enum for the whole of it, so a view draws the state it is in rather than reading three
/// booleans and guessing what they mean together. The road rides along from the first attempt,
/// since "connecting over the relay" and "connecting on the network" are different waits and
/// the person is owed the difference.
public enum LinkConnectionState: Equatable, Sendable {
    /// Nothing is connected and nothing is being tried.
    case offline
    /// Looking for the Mac: the stored addresses first, then Bonjour.
    case searching
    /// A road is being opened.
    case connecting(LinkRoad)
    /// The road is open and the handshake is running.
    case handshaking(LinkRoad)
    /// The channel is sealed and the session is live.
    case live(LinkRoad)
    /// It did not work, in the words to show.
    case failed(String)
    /// It did not work, and the next attempt is at a known moment.
    ///
    /// `failed` and nothing else used to be the whole of a drop, which read as "that is that"
    /// while the phone was in fact about to dial again a second later. The reason is the
    /// sentence the failure carried, kept because it is still why nothing is connected; the
    /// date is what lets a view count down to the attempt and offer to skip the wait.
    case waiting(reason: String, until: Date)

    /// The road in use, where there is one.
    public var road: LinkRoad? {
        switch self {
        case .connecting(let road), .handshaking(let road), .live(let road): road
        case .offline, .searching, .failed, .waiting: nil
        }
    }

    /// Whether the session is live and commands may be sent.
    public var isLive: Bool { if case .live = self { true } else { false } }

    /// Whether a connection is already being made, which is what makes `connect()` idempotent.
    ///
    /// A wait is not busy: nothing is open, nothing is being opened, and the next attempt is
    /// exactly what `connect()` is. A wait that read as busy would be a Retry Now that did
    /// nothing.
    public var isBusy: Bool {
        switch self {
        case .searching, .connecting, .handshaking, .live: true
        case .offline, .failed, .waiting: false
        }
    }

    /// When the next attempt is due, for a state that is waiting for one.
    public var nextAttempt: Date? {
        if case .waiting(_, let date) = self { return date }
        return nil
    }

    /// Why nothing is connected, where something has said why.
    public var reason: String? {
        switch self {
        case .failed(let reason), .waiting(let reason, _): reason
        case .offline, .searching, .connecting, .handshaking, .live: nil
        }
    }
}
