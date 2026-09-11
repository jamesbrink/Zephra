import CryptoKit
import Foundation

/// The phone's side of the handshake: it opens, and it closes.
///
/// A class because it holds one connection's ephemeral key between the two messages, and that
/// key must never be reused: a second connection makes a second initiator.
public final class HandshakeInitiator {
    private let identity: DeviceIdentity
    private let peer: DevicePublicKeys
    private let pairingSecret: Data?
    private let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    private let nonce = RandomBytes.make(HandshakeAgreement.nonceByteCount)
    private let deviceName: String
    private var sent: Hello?

    /// Prepares a handshake with one Mac.
    ///
    /// The secret is the one out of the QR code on a first connection, and nil on every
    /// reconnection after it, where the static keys are what the two ends already share.
    public init(
        identity: DeviceIdentity, peer: DevicePublicKeys, pairingSecret: Data?, deviceName: String
    ) {
        self.identity = identity
        self.peer = peer
        self.pairingSecret = pairingSecret
        self.deviceName = deviceName
    }

    /// The opening message, which is also what the transcript is hashed from.
    public func hello() -> Hello {
        if let sent { return sent }
        let message = Hello(
            ephemeral: ephemeral.publicKey.rawRepresentation,
            keys: identity.publicKeys,
            nonce: nonce,
            pairing: pairingSecret != nil,
            deviceName: deviceName)
        sent = message
        return message
    }

    /// Checks the Mac's proof and answers with the phone's, giving the channel to talk over.
    ///
    /// The Mac's tag is checked here rather than after the channel opens, so a wrong pairing
    /// secret is a refusal the person can be shown rather than a frame that will not decrypt.
    public func receive(_ accept: Accept) throws -> (confirm: Confirm, channel: SecureChannel) {
        let transcript = try HandshakeTranscript.make(
            hello: hello(), responderEphemeral: accept.ephemeral, responderNonce: accept.nonce)
        let keys = HandshakeKeys(
            inputKeyMaterial: try HandshakeAgreement.inputKeyMaterial(
                initiatorEphemeral: ephemeral.publicKey,
                initiatorStatic: identity.agreement.publicKey,
                responderEphemeral: try Curve25519.KeyAgreement.PublicKey(
                    rawRepresentation: accept.ephemeral),
                responderStatic: try peer.agreementKey(),
                ownEphemeral: ephemeral,
                ownStatic: identity.agreement,
                isInitiator: true),
            pairingSecret: pairingSecret,
            transcript: transcript)
        guard keys.isResponderTag(accept.tag, transcript: transcript) else {
            throw LinkError(
                code: .refused,
                reason: "That Mac answered with the wrong code. Show the pairing code again.")
        }
        return (
            Confirm(tag: keys.initiatorTag(transcript)),
            SecureChannel(
                sendKey: keys.initiatorToResponder, receiveKey: keys.responderToInitiator)
        )
    }
}
