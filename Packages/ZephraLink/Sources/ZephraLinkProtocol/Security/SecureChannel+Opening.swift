import CryptoKit
import Foundation

/// Taking one sealed frame apart, which is the half of the channel that has to be careful.
extension SecureChannel {
    /// The smallest a sealed frame can be: the kind byte, the counter and a tag, with at least a
    /// byte of body under it.
    static var sealedFloor: Int { 1 + counterByteCount + 16 }

    /// The counter those bytes carry, read before anything is decrypted: it is the nonce the
    /// decryption needs and the number the window is checked against.
    static func counter(in data: Data) throws -> UInt64 {
        guard data.count > sealedFloor else { throw SecureChannelError.undecipherable }
        return data.dropFirst().prefix(counterByteCount)
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }

    /// The frame those bytes are under `key`.
    ///
    /// Split out so the arithmetic on the counter and the failure that closes the channel stay in
    /// one short method each: this one only ever throws, and the caller only ever closes.
    static func unseal(_ data: Data, key: SymmetricKey) throws -> Frame {
        guard let kind = data.first, data.count > sealedFloor else {
            throw SecureChannelError.undecipherable
        }
        let sealed = data.dropFirst(1 + counterByteCount)
        let box = try AES.GCM.SealedBox(
            nonce: try nonce(try counter(in: data)),
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
