import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("A recorded handshake cannot be played back at the Mac")
struct HandshakeReplayTests {
    @Test("The same hello at a fresh Mac derives different keys and the old confirm fails")
    func replayedHelloCannotFinish() throws {
        let secret = PairingSecret()
        let phone = DeviceIdentity()
        let mac = DeviceIdentity()
        let initiator = HandshakeInitiator(
            identity: phone, peer: mac.publicKeys, pairingSecret: secret.bytes,
            deviceName: "Test Phone")
        let hello = initiator.hello()

        let first = HandshakeResponder(
            identity: mac, isKnown: { _ in false }, pairingSecret: secret.bytes)
        let (confirm, _) = try initiator.receive(try first.receive(hello))

        // The same hello, recorded off the wire, replayed at a Mac that has restarted its
        // handshake: a new ephemeral and a new nonce make a new transcript, so the tag the
        // phone computed for the first exchange proves nothing about this one.
        let second = HandshakeResponder(
            identity: mac, isKnown: { _ in false }, pairingSecret: secret.bytes)
        let accept = try second.receive(hello)
        #expect(throws: LinkError.self) { try second.receive(confirm) }
        #expect(accept.nonce != hello.nonce)
    }

    @Test("A confirm before a hello is refused")
    func confirmWithoutHelloIsRefused() {
        let responder = HandshakeResponder(
            identity: DeviceIdentity(), isKnown: { _ in true }, pairingSecret: nil)
        #expect(throws: LinkError.self) { try responder.receive(Confirm(tag: Data(count: 32))) }
    }

    @Test("A forged confirm under the wrong key is refused")
    func forgedConfirmIsRefused() throws {
        let mac = DeviceIdentity()
        let phone = DeviceIdentity()
        let responder = HandshakeResponder(
            identity: mac, isKnown: { $0 == phone.publicKeys }, pairingSecret: nil)
        let initiator = HandshakeInitiator(
            identity: phone, peer: mac.publicKeys, pairingSecret: nil, deviceName: "Test Phone")
        _ = try responder.receive(initiator.hello())
        #expect(throws: LinkError.self) { try responder.receive(Confirm(tag: Data(count: 32))) }
    }
}
