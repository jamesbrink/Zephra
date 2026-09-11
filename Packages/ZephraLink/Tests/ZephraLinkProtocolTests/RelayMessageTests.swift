import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("The relay is told who may join a room and nothing else")
struct RelayMessageTests {
    @Test("A join signed for one room verifies, and the same signature does not open another")
    func joinIsBoundToItsRoom() throws {
        let mac = DeviceIdentity()
        let nonce = Data((0..<16).map { UInt8($0) })
        let signature = try RelayJoin.sign(
            identity: mac, room: mac.roomID, role: .host, nonce: nonce)
        #expect(
            RelayJoin.verify(
                signature: signature, publicKey: mac.publicKeys.signing, room: mac.roomID,
                role: .host, nonce: nonce))
        #expect(
            !RelayJoin.verify(
                signature: signature, publicKey: mac.publicKeys.signing,
                room: DeviceIdentity().roomID, role: .host, nonce: nonce))
        #expect(
            !RelayJoin.verify(
                signature: signature, publicKey: mac.publicKeys.signing, room: mac.roomID,
                role: .guest, nonce: nonce))
        #expect(
            !RelayJoin.verify(
                signature: signature, publicKey: mac.publicKeys.signing, room: mac.roomID,
                role: .host, nonce: Data(count: 16)))
    }

    @Test("A signature from another device does not verify")
    func anotherDeviceCannotJoin() throws {
        let mac = DeviceIdentity()
        let nonce = Data(count: 16)
        let signature = try RelayJoin.sign(
            identity: DeviceIdentity(), room: mac.roomID, role: .host, nonce: nonce)
        #expect(
            !RelayJoin.verify(
                signature: signature, publicKey: mac.publicKeys.signing, room: mac.roomID,
                role: .host, nonce: nonce))
    }

    @Test("Every relay message survives being written and read back")
    func messagesRoundTrip() throws {
        let mac = DeviceIdentity()
        let messages: [RelayMessage] = [
            .challenge(nonce: Data(count: 16)),
            try RelayJoin.message(
                identity: mac, room: mac.roomID, role: .host, nonce: Data(count: 16)),
            .send(payload: Data([1, 2, 3])),
            .peer(event: .joined),
        ]
        for message in messages {
            #expect(try LinkFixtures.roundTrip(message) == message)
        }
    }

    @Test("A join is one JSON object with base64 keys, which a text frame carries")
    func joinIsTextFriendly() throws {
        let mac = DeviceIdentity()
        let message = try RelayJoin.message(
            identity: mac, room: mac.roomID, role: .guest, nonce: Data([0xAA, 0xBB]))
        let json = String(decoding: try LinkJSON.encode(message), as: UTF8.self)
        #expect(json.hasPrefix("{\"a\":\"join\""))
        #expect(json.contains("\"o\":\"guest\""))
        #expect(json.contains("\"r\":\"\(mac.roomID.rawValue)\""))
        #expect(json.allSatisfy { $0.isASCII })
    }
}
