import Foundation

/// What a device and the relay say to each other.
///
/// The relay never sees inside a `send`: its payload is one sealed frame, and the relay has no
/// key. What it does is check that a joiner holds the private key it claims, that a host's key
/// hashes to the room, that a guest is on the host's allow-list or that the host has declared
/// the room open, and then copy bytes between the two ends.
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
    ///
    /// `allow` is the host's alone: every paired device's raw signing key, which is the set the
    /// relay admits a guest out of. Nil from a guest, and nil from a host that has paired
    /// nothing, which admits nobody.
    ///
    /// `open` is the host's alone too: true while a pairing code is on screen, and the one thing
    /// that lets a guest in whose key is on no list yet. Omitted when false — a room is shut
    /// unless the Mac says otherwise.
    case join(
        room: RoomID, publicKey: Data, role: RelayRole, signature: Data, allow: [Data]? = nil,
        open: Bool? = nil)
    /// The relay let it in, as this role.
    case joined(role: RelayRole)
    /// The host replacing its allow-list, because a device was paired or revoked, or saying
    /// whether its room is open because a code went up or came down. Nothing else may send one:
    /// a guest that tries is told `not host`.
    case allow(pubs: [Data], open: Bool? = nil)
    /// The relay's receipt for an `allow`, saying how many keys it now holds.
    case allowed(count: Int)
    /// The relay refused. Before a join it closes the connection after this; after a join it
    /// does not.
    case error(reason: String)
    /// One sealed frame, to be copied to the other end verbatim.
    ///
    /// The three fragment fields are one slice of a payload too big for a single WebSocket
    /// frame: `message` (`m`) the id every slice of one payload shares, `index` (`i`) which
    /// slice this is and `count` (`n`) how many there are. All three are absent on a payload
    /// that fits, which is every frame a previous build sent. The relay neither reads nor
    /// rewrites them — a `send` is forwarded verbatim — so reassembly is the receiver's,
    /// `RelayFragments`.
    ///
    /// The last two are the room's several guests. `to` is the host's, naming which phone the
    /// frame is for, since the host has one socket for all of them; a host that names none is
    /// answered `ambiguous` where there is more than one. `from` is the relay's, written on
    /// every frame it hands a host, and never read from a sender: a guest that writes its own is
    /// overwritten. Both are absent between a phone and a relay that has not got them, which is
    /// what keeps an older Mac and an older relay working unchanged.
    case send(
        payload: Data, message: String? = nil, index: Int? = nil, count: Int? = nil,
        to: String? = nil, from: String? = nil)
    /// The other end arrived or went. A guest leaving notifies the host too, and `from` is which
    /// guest it was; a phone is told nothing of the kind, so it reads nil.
    case peer(event: RelayPeerEvent, from: String? = nil)
    /// Keep the connection alive. Every five minutes, against a ten-minute idle timeout.
    case ping
    /// The answer to a ping.
    case pong
    /// Something that is not the relay's at all: API Gateway's own JSON, which carries a
    /// `message` and no `a`.
    ///
    /// The gateway sits in front of the relay and answers for itself — `{"message":"Forbidden"}`
    /// when a route refuses, `{"message":"Internal server error"}` when the Lambda throws — and
    /// nothing in the relay's own contract has that shape. Without a case for it the read failed
    /// to decode and took the road down, so one bad invocation in the middle of a picture cost
    /// the whole session instead of the one frame the gateway swallowed. It is carried up as a
    /// road error, which is what the far end's gap will be about.
    case foreign(message: String)

    /// The tag, which is also the case name.
    ///
    /// `foreign` is never written as `a` and never read from one: it is the *absence* of `a`,
    /// and it is in this list so that every case has exactly one tag to be named by.
    public enum Action: String, Codable, Hashable, Sendable, CaseIterable {
        case hello, challenge, join, joined, allow, allowed, error, send, peer, ping, pong, foreign
    }

    /// Whether this message declares the room open to a guest that is on no list yet.
    ///
    /// Absent and false are the same answer, and the encoding writes neither, so this is the one
    /// place either is read: a room is shut unless a host says otherwise.
    public var isOpen: Bool {
        switch self {
        case .join(_, _, _, _, _, let open), .allow(_, let open): open == true
        default: false
        }
    }

    /// Which guest of the room this came from, where the relay named one.
    ///
    /// Nil from a relay that does not name guests, and nil on everything a phone is sent: it has
    /// one peer and needs no id for it. The Mac routes by this, so it is read in one place.
    public var from: String? {
        switch self {
        case .send(_, _, _, _, _, let from), .peer(_, let from): from
        default: nil
        }
    }

    /// Which message this is, without decoding its payload.
    public var action: Action {
        switch self {
        case .hello: .hello
        case .challenge: .challenge
        case .join: .join
        case .joined: .joined
        case .allow: .allow
        case .allowed: .allowed
        case .error: .error
        case .send: .send
        case .peer: .peer
        case .ping: .ping
        case .pong: .pong
        case .foreign: .foreign
        }
    }
}
