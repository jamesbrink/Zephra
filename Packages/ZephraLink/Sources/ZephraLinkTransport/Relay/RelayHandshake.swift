import Foundation
import ZephraLinkProtocol

/// Getting into a room, as a value with no socket under it.
///
/// The sequence is four messages and a handful of rules about which may follow which, and all
/// of them are worth a test. Kept apart from `RelayConnection` so they can have one without a
/// server: hand it the messages a relay would send and it says what to send back.
public struct RelayHandshake: Sendable {
    /// What to do with the message that just arrived.
    public enum Step: Hashable, Sendable {
        /// Send this and keep waiting.
        case send(RelayMessage)
        /// The room is joined; everything after this is traffic.
        case joined
        /// Nothing to do, keep waiting. A relay may answer a ping at any time.
        case ignore
    }

    private let identity: DeviceIdentity
    private let room: RoomID
    private let role: RelayRole

    /// Prepares to join one room as one role.
    public init(identity: DeviceIdentity, room: RoomID, role: RelayRole) {
        self.identity = identity
        self.room = room
        self.role = role
    }

    /// The first message, which asks for a challenge.
    public var opening: RelayMessage { .hello }

    /// What the relay's message means.
    ///
    /// A `send` or a `peer` before the join is out of turn rather than early traffic: the relay
    /// forwards nothing to a connection it has no membership for, so either the relay is not
    /// the one this protocol describes or something is in the middle.
    ///
    /// `allow` is read at the moment the challenge lands rather than held here, because a
    /// pairing may complete or be revoked between opening the socket and answering: the list
    /// that goes out is the one the Mac holds as it joins.
    public func receive(_ message: RelayMessage, allow: [Data] = []) throws -> Step {
        switch message {
        case .challenge(let nonce):
            return .send(
                try RelayJoin.message(
                    identity: identity, nonce: nonce, room: room, role: role, allow: allow))
        case .joined(let granted):
            guard granted == role else { throw RelayError.refused("bad role") }
            return .joined
        case .error(let reason):
            throw RelayError.refused(reason)
        case .pong, .ping:
            return .ignore
        case .hello, .join, .allow, .allowed, .send, .peer:
            throw RelayError.unexpected(message.action)
        }
    }
}
