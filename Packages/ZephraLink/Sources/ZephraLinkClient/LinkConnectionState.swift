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

    /// The road in use, where there is one.
    public var road: LinkRoad? {
        switch self {
        case .connecting(let road), .handshaking(let road), .live(let road): road
        case .offline, .searching, .failed: nil
        }
    }

    /// Whether the session is live and commands may be sent.
    public var isLive: Bool { if case .live = self { true } else { false } }

    /// Whether a connection is already being made, which is what makes `connect()` idempotent.
    public var isBusy: Bool {
        switch self {
        case .searching, .connecting, .handshaking, .live: true
        case .offline, .failed: false
        }
    }
}
