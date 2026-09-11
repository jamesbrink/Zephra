import Foundation

/// One addressed message: what it is, who it answers, and its body as bytes.
///
/// The body stays `Data` rather than becoming an associated value per kind, so a message whose
/// kind this build does not know is still a well-formed envelope that can be logged and
/// refused rather than a parse failure that kills the connection.
public struct Envelope: Codable, Hashable, Sendable {
    /// This message's identity, which a reply quotes.
    public let id: UUID
    /// What the body is.
    public let kind: MessageKind
    /// The request this answers, or nil for anything unsolicited.
    public let inReplyTo: UUID?
    /// The body, JSON in the `LinkJSON` spelling.
    public let body: Data

    /// Creates an envelope around an already-encoded body.
    public init(id: UUID = UUID(), kind: MessageKind, inReplyTo: UUID? = nil, body: Data) {
        self.id = id
        self.kind = kind
        self.inReplyTo = inReplyTo
        self.body = body
    }

    /// An envelope carrying `value` as its body.
    public static func encoding<T: Encodable>(
        _ value: T, kind: MessageKind, inReplyTo: UUID? = nil
    ) throws -> Envelope {
        Envelope(kind: kind, inReplyTo: inReplyTo, body: try LinkJSON.encode(value))
    }

    /// The body read back as `type`.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try LinkJSON.decode(type, from: body)
    }
}
