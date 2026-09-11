import Foundation

/// What a device and the relay say to each other.
///
/// The relay never sees inside a `send`: its payload is one sealed frame, and the relay has no
/// key. All it does is check that a joiner holds the private key for the room it asks for, and
/// then copy bytes between the two ends.
///
/// JSON, because API Gateway's WebSocket API carries text frames: a binary protocol would need
/// a second encoding anyway. The discriminator is `a`, for action, and it is the only field
/// every case has.
public enum RelayMessage: Hashable, Sendable {
    /// The client opens. The relay answers with a challenge.
    case hello
    /// The relay's challenge: thirty-two random bytes to sign. Single-use, and good for sixty
    /// seconds; a second `hello` replaces it.
    case challenge(nonce: Data)
    /// A device asking to join a room, proving it may.
    case join(room: RoomID, publicKey: Data, role: RelayRole, signature: Data)
    /// The relay let it in, as this role.
    case joined(role: RelayRole)
    /// The relay refused. Before a join it closes the connection after this; after a join it
    /// does not.
    case error(reason: String)
    /// One sealed frame, to be copied to the other end verbatim.
    case send(payload: Data)
    /// The other end arrived or went. A guest leaving notifies the host too.
    case peer(event: RelayPeerEvent)
    /// Keep the connection alive. Every five minutes, against a ten-minute idle timeout.
    case ping
    /// The answer to a ping.
    case pong

    /// The tag, which is also the case name.
    public enum Action: String, Codable, Hashable, Sendable, CaseIterable {
        case hello, challenge, join, joined, error, send, peer, ping, pong
    }

    /// Which message this is, without decoding its payload.
    public var action: Action {
        switch self {
        case .hello: .hello
        case .challenge: .challenge
        case .join: .join
        case .joined: .joined
        case .error: .error
        case .send: .send
        case .peer: .peer
        case .ping: .ping
        case .pong: .pong
        }
    }
}
