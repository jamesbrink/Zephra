import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("Two devices agree on a channel, or do not talk at all")
struct HandshakeTests {
    /// One end of a completed handshake each way.
    struct Pair {
        let phone: SecureChannel
        let mac: SecureChannel
        let peer: DevicePublicKeys
        let paired: Bool
    }

    /// A whole handshake, run in memory.
    static func handshake(
        phone: DeviceIdentity = DeviceIdentity(),
        mac: DeviceIdentity = DeviceIdentity(),
        initiatorSecret: Data?,
        responderSecret: Data?,
        isKnown: @escaping @Sendable (DevicePublicKeys) -> Bool = { _ in false }
    ) throws -> Pair {
        let initiator = HandshakeInitiator(
            identity: phone, peer: mac.publicKeys, pairingSecret: initiatorSecret,
            deviceName: "Test Phone")
        let responder = HandshakeResponder(
            identity: mac, isKnown: isKnown, pairingSecret: responderSecret)
        let accept = try responder.receive(initiator.hello())
        let (confirm, phoneChannel) = try initiator.receive(accept)
        let settled = try responder.receive(confirm)
        return Pair(
            phone: phoneChannel, mac: settled.channel, peer: settled.peer, paired: settled.paired)
    }

    @Test("Pairing with the code succeeds and both ends can read each other")
    func pairingSucceeds() throws {
        let secret = PairingSecret()
        let phone = DeviceIdentity()
        let pair = try Self.handshake(
            phone: phone, initiatorSecret: secret.bytes, responderSecret: secret.bytes)
        #expect(pair.paired)
        #expect(pair.peer == phone.publicKeys)
        let ping = Frame.envelope(Envelope(kind: .ping, body: Data("{}".utf8)))
        #expect(try pair.mac.open(try pair.phone.seal(ping)) == ping)
        #expect(try pair.phone.open(try pair.mac.seal(ping)) == ping)
    }

    @Test("A pairing secret that does not match is refused")
    func wrongSecretIsRefused() {
        #expect(throws: LinkError.self) {
            try Self.handshake(
                initiatorSecret: PairingSecret().bytes, responderSecret: PairingSecret().bytes)
        }
    }

    @Test("A request to pair with no code on screen is refused")
    func pairingWithoutALiveSecretIsRefused() throws {
        let responder = HandshakeResponder(
            identity: DeviceIdentity(), isKnown: { _ in false }, pairingSecret: nil)
        let initiator = HandshakeInitiator(
            identity: DeviceIdentity(), peer: DeviceIdentity().publicKeys,
            pairingSecret: PairingSecret().bytes, deviceName: "Test Phone")
        #expect(throws: LinkError.refused) { try responder.receive(initiator.hello()) }
    }

    @Test("A device the Mac does not know is turned away when it is not pairing")
    func unknownDeviceIsNotPaired() throws {
        let responder = HandshakeResponder(
            identity: DeviceIdentity(), isKnown: { _ in false }, pairingSecret: nil)
        let initiator = HandshakeInitiator(
            identity: DeviceIdentity(), peer: DeviceIdentity().publicKeys, pairingSecret: nil,
            deviceName: "Test Phone")
        #expect(throws: LinkError.notPaired) { try responder.receive(initiator.hello()) }
    }

    @Test("A device the Mac knows reconnects with no code at all")
    func knownDeviceReconnects() throws {
        let phone = DeviceIdentity()
        let pair = try Self.handshake(
            phone: phone, initiatorSecret: nil, responderSecret: nil,
            isKnown: { $0 == phone.publicKeys })
        #expect(!pair.paired)
        let ping = Frame.envelope(Envelope(kind: .ping, body: Data("{}".utf8)))
        #expect(try pair.mac.open(try pair.phone.seal(ping)) == ping)
    }

    @Test("A protocol this Mac does not speak stops before any key is derived")
    func versionMismatchStops() throws {
        let responder = HandshakeResponder(
            identity: DeviceIdentity(), isKnown: { _ in true }, pairingSecret: nil)
        let hello = Hello(
            version: LinkProtocolVersion.current + 1,
            ephemeral: DeviceIdentity().publicKeys.keyAgreement,
            keys: DeviceIdentity().publicKeys, nonce: Data(count: 16), pairing: false,
            deviceName: "Test Phone")
        #expect(throws: LinkError.protocolMismatch) { try responder.receive(hello) }
    }
}
