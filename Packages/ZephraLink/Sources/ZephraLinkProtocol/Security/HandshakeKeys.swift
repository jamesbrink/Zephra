import CryptoKit
import Foundation

/// The three keys a handshake ends with, and the schedule that derives them.
///
/// A Noise-style pattern: four Diffie-Hellman results concatenated as one input, the pairing
/// secret as the salt, and the transcript in the info string. Mixing all four means the channel
/// is only as good as every one of them — an attacker who has the ephemeral keys still lacks the
/// static ones, and one who has a static key still lacks the ephemerals, so a stolen identity
/// does not read yesterday's traffic.
struct HandshakeKeys {
    /// How many bytes the schedule produces: three thirty-two byte keys.
    static let derivedByteCount = 96
    /// What the info string is prefixed with, so these keys are good for this protocol alone.
    static let info = Data("zephra-link-v1".utf8)

    /// What the phone seals with and the Mac opens with.
    let initiatorToResponder: SymmetricKey
    /// What the Mac seals with and the phone opens with.
    let responderToInitiator: SymmetricKey
    /// What both tags are computed under.
    let confirmation: SymmetricKey

    /// The keys for one handshake.
    ///
    /// `ikm` is `ee || es || se || ss`; the salt is the pairing secret, or thirty-two zero bytes
    /// on a reconnection, where the static keys are what stand in for it.
    init(inputKeyMaterial: Data, pairingSecret: Data?, transcript: Data) {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: inputKeyMaterial),
            salt: pairingSecret ?? Data(count: 32),
            info: Self.info + transcript,
            outputByteCount: Self.derivedByteCount)
        let bytes = derived.withUnsafeBytes { Data($0) }
        initiatorToResponder = SymmetricKey(data: bytes.prefix(32))
        responderToInitiator = SymmetricKey(data: bytes.dropFirst(32).prefix(32))
        confirmation = SymmetricKey(data: bytes.suffix(32))
    }

    /// The Mac's tag over a transcript.
    func responderTag(_ transcript: Data) -> Data { tag(prefix: "r", transcript) }

    /// The phone's tag over a transcript.
    func initiatorTag(_ transcript: Data) -> Data { tag(prefix: "i", transcript) }

    /// Whether `tag` is the Mac's, checked in constant time.
    func isResponderTag(_ candidate: Data, transcript: Data) -> Bool {
        isValid(candidate, prefix: "r", transcript)
    }

    /// Whether `tag` is the phone's, checked in constant time.
    func isInitiatorTag(_ candidate: Data, transcript: Data) -> Bool {
        isValid(candidate, prefix: "i", transcript)
    }

    private func tag(prefix: String, _ transcript: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: Data(prefix.utf8) + transcript, using: confirmation))
    }

    private func isValid(_ candidate: Data, prefix: String, _ transcript: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            candidate, authenticating: Data(prefix.utf8) + transcript, using: confirmation)
    }
}
