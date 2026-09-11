/// What an `Envelope` carries, which is what the receiver switches on before it decodes a body.
///
/// A string rather than an integer, so a packet capture and a log line read as English and an
/// unknown kind from a newer build is reported by name.
public enum MessageKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// The initiator opens the handshake. Plaintext.
    case hello
    /// The responder answers it. Plaintext.
    case accept
    /// The initiator closes it. Plaintext; everything after this is sealed.
    case confirm
    /// The whole of the Mac's state, sent once when a session opens.
    case snapshot
    /// One change to that state.
    case delta
    /// A frame of the run in flight.
    case preview
    /// A `Command` from the phone.
    case request
    /// The `Reply` to one, carrying the request's id in `inReplyTo`.
    case reply
    /// A blob is about to follow as chunks.
    case blobStart
    /// Something went wrong, carrying a `LinkError`.
    case error
    /// Keep the connection alive.
    case ping
    /// The answer to a ping.
    case pong
}
