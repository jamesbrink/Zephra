import CryptoKit
import Foundation

/// The Mac's side of the handshake: it answers, and it decides who may talk to it.
///
/// Two questions, kept apart. Whether this device is allowed at all is `isKnown` and the live
/// pairing secret, answered before any key is derived. Whether it is who it says it is, is the
/// tag on the `Confirm`, answered after.
public final class HandshakeResponder {
    private let identity: DeviceIdentity
    private let isKnown: @Sendable (DevicePublicKeys) -> Bool
    private let pairingSecret: Data?
    private let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    private let nonce = RandomBytes.make(HandshakeAgreement.nonceByteCount)
    private var pending: (hello: Hello, transcript: Data, keys: HandshakeKeys)?

    /// Prepares to answer one connection.
    ///
    /// The secret is the one behind the QR code on screen, and nil whenever no code is up,
    /// which is what makes a request to pair refusable without asking the person again.
    public init(
        identity: DeviceIdentity,
        isKnown: @escaping @Sendable (DevicePublicKeys) -> Bool,
        pairingSecret: Data?
    ) {
        self.identity = identity
        self.isKnown = isKnown
        self.pairingSecret = pairingSecret
    }

    /// Answers the opening message, or refuses it.
    public func receive(_ hello: Hello) throws -> Accept {
        guard hello.version == LinkProtocolVersion.current else { throw LinkError.protocolMismatch }
        if hello.pairing {
            guard pairingSecret != nil else { throw LinkError.refused }
        } else {
            guard isKnown(hello.keys) else { throw LinkError.notPaired }
        }
        let transcript = try HandshakeTranscript.make(
            hello: hello, responderEphemeral: ephemeral.publicKey.rawRepresentation,
            responderNonce: nonce)
        let keys = HandshakeKeys(
            inputKeyMaterial: try HandshakeAgreement.inputKeyMaterial(
                initiatorEphemeral: try Curve25519.KeyAgreement.PublicKey(
                    rawRepresentation: hello.ephemeral),
                initiatorStatic: try hello.keys.agreementKey(),
                responderEphemeral: ephemeral.publicKey,
                responderStatic: identity.agreement.publicKey,
                ownEphemeral: ephemeral,
                ownStatic: identity.agreement,
                isInitiator: false),
            pairingSecret: hello.pairing ? pairingSecret : nil,
            transcript: transcript)
        pending = (hello, transcript, keys)
        return Accept(
            ephemeral: ephemeral.publicKey.rawRepresentation, nonce: nonce,
            tag: keys.responderTag(transcript))
    }

    /// Checks the phone's proof and gives the channel, who it was, and whether this paired it.
    public func receive(
        _ confirm: Confirm
    ) throws -> (channel: SecureChannel, peer: DevicePublicKeys, paired: Bool) {
        guard let pending else {
            throw LinkError(code: .badRequest, reason: "That device has not said hello yet.")
        }
        guard pending.keys.isInitiatorTag(confirm.tag, transcript: pending.transcript) else {
            throw LinkError(
                code: .refused,
                reason: "That device answered with the wrong code. Show the pairing code again.")
        }
        return (
            SecureChannel(
                sendKey: pending.keys.responderToInitiator,
                receiveKey: pending.keys.initiatorToResponder),
            pending.hello.keys,
            pending.hello.pairing
        )
    }
}
