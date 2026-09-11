/// Which way the phone reached the Mac.
///
/// The interface says which, because they are not the same promise: the local network is fast
/// and private, and the relay is a hop through somebody else's machine that works from
/// anywhere. Nothing below the interface branches on it — a `LinkConnection` is a
/// `LinkConnection`.
public enum LinkRoad: Hashable, Sendable {
    /// A TCP connection on the local network.
    case lan
    /// A room on the WebSocket relay.
    case relay
}
