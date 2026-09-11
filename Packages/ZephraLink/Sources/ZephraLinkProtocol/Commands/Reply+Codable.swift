import Foundation

/// The JSON one reply is: a tagged object, for the reason `Command`'s is.
extension Reply: Codable {
    private enum CodingKeys: String, CodingKey { case kind, batchID, blob, page, error }

    /// The tag, which is also the case name.
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case ok, queued, blob, entries, error
    }

    /// Which reply this is, without decoding its payload.
    public var kind: Kind {
        switch self {
        case .ok: .ok
        case .queued: .queued
        case .blob: .blob
        case .entries: .entries
        case .error: .error
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .ok: break
        case .queued(let batchID): try container.encode(batchID, forKey: .batchID)
        case .blob(let start): try container.encode(start, forKey: .blob)
        case .entries(let page): try container.encode(page, forKey: .page)
        case .error(let error): try container.encode(error, forKey: .error)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .ok: self = .ok
        case .queued: self = .queued(batchID: try container.decode(UUID.self, forKey: .batchID))
        case .blob: self = .blob(try container.decode(BlobStart.self, forKey: .blob))
        case .entries: self = .entries(try container.decode(LibraryPage.self, forKey: .page))
        case .error: self = .error(try container.decode(LinkError.self, forKey: .error))
        }
    }
}
