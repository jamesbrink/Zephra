import CryptoKit
import Foundation

/// What both ends hash to be sure they saw the same handshake.
///
/// The whole of the first message, byte for byte, then the Mac's ephemeral key and its nonce.
/// The `Hello` is re-encoded from the value the Mac decoded rather than kept as received, which
/// is safe exactly because `LinkJSON` sorts its keys: two encodings of the same value are the
/// same bytes, and a field the Mac cannot decode is a handshake that stops before this.
enum HandshakeTranscript {
    /// The transcript for one handshake.
    static func make(hello: Hello, responderEphemeral: Data, responderNonce: Data) throws -> Data {
        var input = try LinkJSON.encode(hello)
        input.append(responderEphemeral)
        input.append(responderNonce)
        return Data(SHA256.hash(data: input))
    }
}
