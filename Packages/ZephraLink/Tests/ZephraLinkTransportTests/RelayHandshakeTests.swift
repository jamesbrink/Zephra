import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraLinkTransport

/// The rules about which relay message may follow which, with no socket in the way.
@Suite("A relay handshake answers a challenge and nothing else")
struct RelayHandshakeTests {
    private let identity = DeviceIdentity()

    @Test("a challenge is answered with a join signed over it, carrying the allow-list")
    func challengeIsSigned() throws {
        let handshake = RelayHandshake(identity: identity, room: identity.roomID, role: .host)
        let nonce = Data(repeating: 7, count: RelayJoin.nonceByteCount)
        let phone = DeviceIdentity().publicKeys.signing
        guard case .send(.join(let room, let publicKey, let role, let signature, let allow)) =
            try handshake.receive(.challenge(nonce: nonce), allow: [phone])
        else { return #expect(Bool(false), "a challenge asks for a join") }
        #expect(room == identity.roomID)
        #expect(role == .host)
        #expect(publicKey == identity.publicKeys.signing)
        #expect(allow == [phone])
        #expect(RelayJoin.verify(
            publicKey: publicKey, nonce: nonce, room: room, role: role, signature: signature))
    }

    @Test("a guest's join carries no allow-list, whatever it is handed")
    func aGuestCarriesNoAllowList() throws {
        let handshake = RelayHandshake(identity: identity, room: identity.roomID, role: .guest)
        guard case .send(.join(_, _, _, _, let allow)) = try handshake.receive(
            .challenge(nonce: Data(repeating: 7, count: RelayJoin.nonceByteCount)),
            allow: [DeviceIdentity().publicKeys.signing])
        else { return #expect(Bool(false), "a challenge asks for a join") }
        #expect(allow == nil)
    }

    @Test("a host that has paired nothing sends an empty list, which admits nobody")
    func aHostWithNoPairingsSendsAnEmptyList() throws {
        let handshake = RelayHandshake(identity: identity, room: identity.roomID, role: .host)
        guard case .send(.join(_, _, _, _, let allow)) = try handshake.receive(
            .challenge(nonce: Data(repeating: 7, count: RelayJoin.nonceByteCount)))
        else { return #expect(Bool(false), "a challenge asks for a join") }
        #expect(allow == [])
    }

    @Test("an allow-list from the relay is out of turn: only a host sends one")
    func anAllowListFromTheRelayIsOutOfTurn() throws {
        let handshake = RelayHandshake(identity: identity, room: identity.roomID, role: .host)
        #expect(throws: RelayError.unexpected(.allow)) {
            try handshake.receive(.allow(pubs: []))
        }
    }

    @Test("the room is joined when the relay says so")
    func joinedEndsIt() throws {
        let handshake = RelayHandshake(identity: identity, room: identity.roomID, role: .guest)
        #expect(try handshake.receive(.joined(role: .guest)) == .joined)
    }

    @Test("a join granted as the other role is a refusal")
    func wrongRoleIsRefused() throws {
        let handshake = RelayHandshake(identity: identity, room: identity.roomID, role: .guest)
        #expect(throws: RelayError.refused("bad role")) {
            try handshake.receive(.joined(role: .host))
        }
    }

    @Test("an error carries the relay's reason through")
    func errorIsTheRelaysOwn() throws {
        let handshake = RelayHandshake(identity: identity, room: identity.roomID, role: .host)
        #expect(throws: RelayError.refused("room does not match key")) {
            try handshake.receive(.error(reason: "room does not match key"))
        }
    }

    @Test("traffic before the join is out of turn, not early traffic")
    func trafficBeforeJoinIsRefused() throws {
        let handshake = RelayHandshake(identity: identity, room: identity.roomID, role: .host)
        #expect(throws: RelayError.unexpected(.send)) {
            try handshake.receive(.send(payload: Data([0x01])))
        }
    }

    @Test("a pong is nothing to answer")
    func pongIsIgnored() throws {
        let handshake = RelayHandshake(identity: identity, room: identity.roomID, role: .host)
        #expect(try handshake.receive(.pong) == .ignore)
    }
}
