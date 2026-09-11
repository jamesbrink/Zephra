import Foundation

/// What a device and the relay say to each other.
///
/// The relay never sees inside a `send`: its payload is one sealed frame, and the relay has no
/// key. All it does is check that a joiner holds the private key for the room it asks for, and
/// then copy bytes between the two ends.
///
/// JSON with base64 payloads, because API Gateway's WebSocket API carries text frames: a binary
/// protocol would need a second encoding anyway. The discriminator is `a`, for action, and it
/// is the only field every case has.
public enum RelayMessage: Codable, Hashable, Sendable {
    /// The relay's opening message: sign this to join.
    case challenge(nonce: Data)
    /// A device asking to join a room, proving it may.
    case join(room: RoomID, publicKey: Data, role: RelayRole, signature: Data)
    /// One sealed frame, to be copied to the other end.
    case send(payload: Data)
    /// The other end arrived or went.
    case peer(event: RelayPeerEvent)

    private enum CodingKeys: String, CodingKey {
        case action = "a"
        case nonce = "n"
        case room = "r"
        case publicKey = "k"
        case role = "o"
        case signature = "s"
        case payload = "p"
        case event = "e"
    }

    /// The tag, which is also the case name.
    public enum Action: String, Codable, Hashable, Sendable, CaseIterable {
        case challenge, join, send, peer
    }

    /// Which message this is, without decoding its payload.
    public var action: Action {
        switch self {
        case .challenge: .challenge
        case .join: .join
        case .send: .send
        case .peer: .peer
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        switch self {
        case .challenge(let nonce): try container.encode(nonce, forKey: .nonce)
        case .join(let room, let publicKey, let role, let signature):
            try container.encode(room, forKey: .room)
            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(role, forKey: .role)
            try container.encode(signature, forKey: .signature)
        case .send(let payload): try container.encode(payload, forKey: .payload)
        case .peer(let event): try container.encode(event, forKey: .event)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Action.self, forKey: .action) {
        case .challenge:
            self = .challenge(nonce: try container.decode(Data.self, forKey: .nonce))
        case .join:
            self = .join(
                room: try container.decode(RoomID.self, forKey: .room),
                publicKey: try container.decode(Data.self, forKey: .publicKey),
                role: try container.decode(RelayRole.self, forKey: .role),
                signature: try container.decode(Data.self, forKey: .signature))
        case .send:
            self = .send(payload: try container.decode(Data.self, forKey: .payload))
        case .peer:
            self = .peer(event: try container.decode(RelayPeerEvent.self, forKey: .event))
        }
    }
}
