import Foundation

/// The JSON one relay message is: a tagged object, for the reason a `Command`'s is.
///
/// The field names are the relay's, not ours. This package is one of two implementations of
/// the same contract — the other is a Lambda — and the names in the deployed one are what both
/// have to agree on. `n` and `d` are the two the relay spells short.
extension RelayMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case action = "a"
        case nonce = "n"
        case room, publicKey = "pub", role, signature = "sig"
        case payload = "d"
        case event, reason
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        switch self {
        case .hello, .ping, .pong: break
        case .challenge(let nonce): try container.encode(nonce, forKey: .nonce)
        case .join(let room, let publicKey, let role, let signature):
            try container.encode(room, forKey: .room)
            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(role, forKey: .role)
            try container.encode(signature, forKey: .signature)
        case .joined(let role): try container.encode(role, forKey: .role)
        case .error(let reason): try container.encode(reason, forKey: .reason)
        case .send(let payload): try container.encode(payload, forKey: .payload)
        case .peer(let event): try container.encode(event, forKey: .event)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) throws -> T {
            try container.decode(type, forKey: key)
        }
        switch try container.decode(Action.self, forKey: .action) {
        case .hello: self = .hello
        case .challenge: self = .challenge(nonce: try value(Data.self, .nonce))
        case .join:
            self = .join(
                room: try value(RoomID.self, .room),
                publicKey: try value(Data.self, .publicKey),
                role: try value(RelayRole.self, .role),
                signature: try value(Data.self, .signature))
        case .joined: self = .joined(role: try value(RelayRole.self, .role))
        case .error: self = .error(reason: try value(String.self, .reason))
        case .send: self = .send(payload: try value(Data.self, .payload))
        case .peer: self = .peer(event: try value(RelayPeerEvent.self, .event))
        case .ping: self = .ping
        case .pong: self = .pong
        }
    }
}
