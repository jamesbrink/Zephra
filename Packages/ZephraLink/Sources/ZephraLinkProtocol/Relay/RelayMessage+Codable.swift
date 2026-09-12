import Foundation

/// The JSON one relay message is: a tagged object, for the reason a `Command`'s is.
///
/// The field names are the relay's, not ours. This package is one of two implementations of
/// the same contract — the other is a Lambda — and the names in the deployed one are what both
/// have to agree on. `n` and `d` are the two the relay spells short.
extension RelayMessage: Codable {
    /// `n` is spelled once and means two things: the challenge's nonce, and how many slices a
    /// fragmented `send` has. They are fields of different messages and the relay's README
    /// spells both that way, so one key carries both rather than the wire growing a synonym.
    private enum CodingKeys: String, CodingKey {
        case action = "a"
        case nonce = "n"
        case room, publicKey = "pub", role, signature = "sig"
        case payload = "d"
        case fragment = "m", index = "i"
        case event, reason
        case allow, pubs, count, open
        /// API Gateway's own word for itself, on the JSON it answers with in front of the relay.
        case foreign = "message"
    }

    /// A flag as the relay spells it: present only when it is true, so a shut room says nothing
    /// and the JSON of every message that has always been sent is unchanged.
    private static func flag(_ value: Bool?) -> Bool? { value == true ? true : nil }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // A foreign message has no `a` at all — that absence is what it *is* — so it is written
        // back exactly as the gateway wrote it and nothing of ours is added to it.
        if case .foreign(let message) = self {
            return try container.encode(message, forKey: .foreign)
        }
        try container.encode(action, forKey: .action)
        switch self {
        case .hello, .ping, .pong: break
        case .challenge(let nonce): try container.encode(nonce, forKey: .nonce)
        case .join(let room, let publicKey, let role, let signature, let allow, let open):
            try container.encode(room, forKey: .room)
            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(role, forKey: .role)
            try container.encode(signature, forKey: .signature)
            try container.encodeIfPresent(allow, forKey: .allow)
            try container.encodeIfPresent(Self.flag(open), forKey: .open)
        case .joined(let role): try container.encode(role, forKey: .role)
        case .allow(let pubs, let open):
            try container.encode(pubs, forKey: .pubs)
            try container.encodeIfPresent(Self.flag(open), forKey: .open)
        case .allowed(let count): try container.encode(count, forKey: .count)
        case .error(let reason): try container.encode(reason, forKey: .reason)
        case .send(let payload, let fragment, let index, let count):
            try container.encode(payload, forKey: .payload)
            try container.encodeIfPresent(fragment, forKey: .fragment)
            try container.encodeIfPresent(index, forKey: .index)
            try container.encodeIfPresent(count, forKey: .nonce)
        case .peer(let event): try container.encode(event, forKey: .event)
        case .foreign: break
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) throws -> T {
            try container.decode(type, forKey: key)
        }
        // No `a` and a `message` is API Gateway answering for itself rather than the relay
        // answering at all. It reads as `foreign` rather than throwing, because throwing here is
        // a road that ends: the decode failure used to cost a whole session over one gateway
        // hiccup in the middle of a picture.
        guard container.contains(.action) else {
            self = .foreign(message: try value(String.self, .foreign))
            return
        }
        switch try container.decode(Action.self, forKey: .action) {
        case .hello: self = .hello
        case .challenge: self = .challenge(nonce: try value(Data.self, .nonce))
        case .join:
            self = .join(
                room: try value(RoomID.self, .room),
                publicKey: try value(Data.self, .publicKey),
                role: try value(RelayRole.self, .role),
                signature: try value(Data.self, .signature),
                allow: try container.decodeIfPresent([Data].self, forKey: .allow),
                open: Self.flag(try container.decodeIfPresent(Bool.self, forKey: .open)))
        case .joined: self = .joined(role: try value(RelayRole.self, .role))
        case .allow:
            self = .allow(
                pubs: try value([Data].self, .pubs),
                open: Self.flag(try container.decodeIfPresent(Bool.self, forKey: .open)))
        case .allowed: self = .allowed(count: try value(Int.self, .count))
        case .error: self = .error(reason: try value(String.self, .reason))
        case .send:
            self = .send(
                payload: try value(Data.self, .payload),
                message: try container.decodeIfPresent(String.self, forKey: .fragment),
                index: try container.decodeIfPresent(Int.self, forKey: .index),
                count: try container.decodeIfPresent(Int.self, forKey: .nonce))
        case .peer: self = .peer(event: try value(RelayPeerEvent.self, .event))
        case .ping: self = .ping
        case .pong: self = .pong
        case .foreign: self = .foreign(message: try value(String.self, .foreign))
        }
    }
}
