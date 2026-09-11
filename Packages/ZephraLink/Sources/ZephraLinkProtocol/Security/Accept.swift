import Foundation

/// The handshake's second message: the Mac answers with its own ephemeral key and proves it
/// derived the same secrets.
public struct Accept: Codable, Hashable, Sendable {
    /// This connection's ephemeral key agreement public key, thirty-two bytes.
    public var ephemeral: Data
    /// Sixteen random bytes, hashed into the transcript beside the phone's.
    public var nonce: Data
    /// The Mac's proof: an HMAC over the transcript under the confirmation key.
    public var tag: Data

    /// Creates the answering message.
    public init(ephemeral: Data, nonce: Data, tag: Data) {
        self.ephemeral = ephemeral
        self.nonce = nonce
        self.tag = tag
    }
}
