import CryptoKit
import Foundation

/// Taking one sealed frame apart, which is the half of the channel that has to be careful.
extension SecureChannel {
    /// The frame those bytes are under `key` at `counter`.
    ///
    /// Split out so the arithmetic on the counter and the failure that closes the channel stay
    /// in one short method each: this one only ever throws, and the caller only ever closes.
    static func unseal(_ data: Data, key: SymmetricKey, counter: UInt64) throws -> Frame {
        guard let kind = data.first, data.count > 1 + 16 else {
            throw SecureChannelError.undecipherable
        }
        let sealed = data.dropFirst()
        let box = try AES.GCM.SealedBox(
            nonce: try nonce(counter),
            ciphertext: sealed.dropLast(16),
            tag: sealed.suffix(16))
        let body: Data
        do {
            body = try AES.GCM.open(box, using: key, authenticating: Data([kind]))
        } catch {
            throw SecureChannelError.undecipherable
        }
        return try FrameCodec.frame(kind: kind, body: body)
    }
}
