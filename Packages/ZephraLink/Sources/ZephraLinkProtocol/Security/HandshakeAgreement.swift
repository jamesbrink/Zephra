import CryptoKit
import Foundation

/// The four Diffie-Hellman results a handshake mixes, in one order both ends agree on.
enum HandshakeAgreement {
    /// How many random bytes a handshake nonce is.
    static let nonceByteCount = 16

    /// `ee || es || se || ss`, from whichever end is asking.
    ///
    /// The names are the initiator's: `es` is the initiator's ephemeral against the responder's
    /// static, `se` the initiator's static against the responder's ephemeral. Both ends compute
    /// the same four secrets from opposite halves, which is why the parameters are spelled by
    /// role and not by "mine" and "theirs".
    static func inputKeyMaterial(
        initiatorEphemeral: Curve25519.KeyAgreement.PublicKey,
        initiatorStatic: Curve25519.KeyAgreement.PublicKey,
        responderEphemeral: Curve25519.KeyAgreement.PublicKey,
        responderStatic: Curve25519.KeyAgreement.PublicKey,
        ownEphemeral: Curve25519.KeyAgreement.PrivateKey,
        ownStatic: Curve25519.KeyAgreement.PrivateKey,
        isInitiator: Bool
    ) throws -> Data {
        let ee = try ownEphemeral.sharedSecretFromKeyAgreement(
            with: isInitiator ? responderEphemeral : initiatorEphemeral)
        let es = isInitiator
            ? try ownEphemeral.sharedSecretFromKeyAgreement(with: responderStatic)
            : try ownStatic.sharedSecretFromKeyAgreement(with: initiatorEphemeral)
        let se = isInitiator
            ? try ownStatic.sharedSecretFromKeyAgreement(with: responderEphemeral)
            : try ownEphemeral.sharedSecretFromKeyAgreement(with: initiatorStatic)
        let ss = try ownStatic.sharedSecretFromKeyAgreement(
            with: isInitiator ? responderStatic : initiatorStatic)
        return [ee, es, se, ss].reduce(into: Data()) { bytes, secret in
            secret.withUnsafeBytes { bytes.append(contentsOf: $0) }
        }
    }
}
