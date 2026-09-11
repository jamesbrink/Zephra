import CryptoKit
import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("The relay is told who may join a room and nothing else")
struct RelayMessageTests {
    static let nonce = Data((0..<32).map { UInt8($0) })

    @Test("A join signed for one room verifies, and the same signature opens nothing else")
    func joinIsBoundToItsChallenge() throws {
        let mac = DeviceIdentity()
        let signature = try RelayJoin.sign(
            identity: mac, nonce: Self.nonce, room: mac.roomID, role: .host)
        #expect(
            RelayJoin.verify(
                publicKey: mac.publicKeys.signing, nonce: Self.nonce, room: mac.roomID,
                role: .host, signature: signature))
        #expect(
            !RelayJoin.verify(
                publicKey: mac.publicKeys.signing, nonce: Self.nonce,
                room: DeviceIdentity().roomID, role: .host, signature: signature))
        #expect(
            !RelayJoin.verify(
                publicKey: mac.publicKeys.signing, nonce: Self.nonce, room: mac.roomID,
                role: .guest, signature: signature))
        #expect(
            !RelayJoin.verify(
                publicKey: mac.publicKeys.signing, nonce: Data(count: 32), room: mac.roomID,
                role: .host, signature: signature))
    }

    @Test("A signature from another device does not verify")
    func anotherDeviceCannotJoin() throws {
        let mac = DeviceIdentity()
        let signature = try RelayJoin.sign(
            identity: DeviceIdentity(), nonce: Self.nonce, room: mac.roomID, role: .host)
        #expect(
            !RelayJoin.verify(
                publicKey: mac.publicKeys.signing, nonce: Self.nonce, room: mac.roomID,
                role: .host, signature: signature))
    }

    @Test("The signed bytes are the nonce, the room and the role, with nothing between them")
    func signedBytesAreExact() {
        let mac = DeviceIdentity()
        let host = RelayJoin.message(nonce: Self.nonce, room: mac.roomID, role: .host)
        let guest = RelayJoin.message(nonce: Self.nonce, room: mac.roomID, role: .guest)
        #expect(host.count == 68)
        #expect(guest.count == 69)
        #expect(host.prefix(32) == Self.nonce)
        #expect(
            String(decoding: host.dropFirst(32), as: UTF8.self) == "\(mac.roomID.rawValue)host")
        #expect(mac.roomID.rawValue.count == 32)
    }

    @Test("The room is the hash of the raw signing key, which is what the relay checks a host on")
    func roomFollowsTheRawKey() {
        let mac = DeviceIdentity()
        let digest = SHA256.hash(data: mac.publicKeys.signing)
        #expect(mac.roomID.rawValue == digest.prefix(16).map { String(format: "%02x", $0) }.joined())
        #expect(mac.publicKeys.signing.count == 32)
    }

    @Test("Every relay message survives being written and read back")
    func messagesRoundTrip() throws {
        let mac = DeviceIdentity()
        let messages: [RelayMessage] = [
            .hello,
            .challenge(nonce: Self.nonce),
            try RelayJoin.message(
                identity: mac, nonce: Self.nonce, room: mac.roomID, role: .host),
            .joined(role: .guest),
            .error(reason: "That room already has a host."),
            .send(payload: Data([1, 2, 3])),
            .peer(event: .joined),
            .ping,
            .pong,
        ]
        #expect(messages.count == RelayMessage.Action.allCases.count)
        for message in messages {
            let read = try LinkFixtures.roundTrip(message)
            #expect(read == message)
            #expect(read.action == message.action)
        }
    }

    @Test("Every action has one exact spelling, which is the relay's and not ours")
    func everyActionHasAGoldenSpelling() throws {
        // The relay is a Lambda written from the same contract, so these strings are the
        // agreement between the two implementations: a rename on either side fails here.
        let goldens: [(RelayMessage, String)] = [
            (.hello, #"{"a":"hello"}"#),
            (.challenge(nonce: Data(repeating: 0xAB, count: 32)),
             #"{"a":"challenge","n":"q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s="}"#),
            (.join(
                room: RoomID(rawValue: "0123456789abcdef0123456789abcdef"),
                publicKey: Data(repeating: 0x01, count: 4), role: .host,
                signature: Data(repeating: 0x02, count: 4)),
             #"{"a":"join","pub":"AQEBAQ==","role":"host","room":"0123456789abcdef0123456789abcdef","sig":"AgICAg=="}"#),
            (.joined(role: .host), #"{"a":"joined","role":"host"}"#),
            (.error(reason: "challenge expired"),
             #"{"a":"error","reason":"challenge expired"}"#),
            (.send(payload: Data([0xAB])), #"{"a":"send","d":"qw=="}"#),
            (.peer(event: .left), #"{"a":"peer","event":"left"}"#),
            (.ping, #"{"a":"ping"}"#),
            (.pong, #"{"a":"pong"}"#),
        ]
        #expect(goldens.count == RelayMessage.Action.allCases.count)
        for (message, golden) in goldens {
            #expect(String(decoding: try LinkJSON.encode(message), as: UTF8.self) == golden)
            #expect(try LinkJSON.decode(RelayMessage.self, from: Data(golden.utf8)) == message)
        }
    }

    @Test("A signed join is ASCII text a 128 KB frame carries easily")
    func joinIsTextFriendly() throws {
        let mac = DeviceIdentity()
        let json = String(
            decoding: try LinkJSON.encode(
                try RelayJoin.message(
                    identity: mac, nonce: Self.nonce, room: mac.roomID, role: .guest)),
            as: UTF8.self)
        #expect(json.allSatisfy { $0.isASCII })
        #expect(json.contains(#""room":"\#(mac.roomID.rawValue)""#))
        #expect(json.count < 300)
    }

    @Test("A challenge is thirty-two bytes and a minute long")
    func challengeIsSized() {
        #expect(RelayJoin.nonceByteCount == 32)
        #expect(RelayJoin.challengeLifetime == 60)
    }
}
