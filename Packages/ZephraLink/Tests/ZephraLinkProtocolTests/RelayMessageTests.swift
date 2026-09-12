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
            .allow(pubs: [Data(repeating: 0x03, count: 32)]),
            .allowed(count: 2),
            .error(reason: "That room already has a host."),
            .send(payload: Data([1, 2, 3])),
            .peer(event: .joined),
            .ping,
            .pong,
            .foreign(message: "Forbidden"),
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
                signature: Data(repeating: 0x02, count: 4),
                allow: [Data(repeating: 0x03, count: 4)]),
             #"{"a":"join","allow":["AwMDAw=="],"pub":"AQEBAQ==","role":"host","room":"0123456789abcdef0123456789abcdef","sig":"AgICAg=="}"#),
            (.joined(role: .host), #"{"a":"joined","role":"host"}"#),
            (.allow(pubs: [Data(repeating: 0x03, count: 4)]),
             #"{"a":"allow","pubs":["AwMDAw=="]}"#),
            (.allowed(count: 2), #"{"a":"allowed","count":2}"#),
            (.error(reason: "challenge expired"),
             #"{"a":"error","reason":"challenge expired"}"#),
            (.send(payload: Data([0xAB])), #"{"a":"send","d":"qw=="}"#),
            (.peer(event: .left), #"{"a":"peer","event":"left"}"#),
            (.ping, #"{"a":"ping"}"#),
            (.pong, #"{"a":"pong"}"#),
            // Not the relay's shape at all: API Gateway's own, which carries no `a`.
            (.foreign(message: "Internal server error"),
             #"{"message":"Internal server error"}"#),
        ]
        #expect(goldens.count == RelayMessage.Action.allCases.count)
        for (message, golden) in goldens {
            #expect(String(decoding: try LinkJSON.encode(message), as: UTF8.self) == golden)
            #expect(try LinkJSON.decode(RelayMessage.self, from: Data(golden.utf8)) == message)
        }
    }

    @Test("A message with no action but a message is the gateway's, not the relay's")
    func theGatewaysOwnJSONIsReadRatherThanRefused() throws {
        // API Gateway sits in front of the relay and answers for itself. Refusing to decode this
        // threw, and a throw in the read loop takes the road down: one gateway hiccup in the
        // middle of a picture cost the whole session rather than the one frame it swallowed.
        #expect(
            try LinkJSON.decode(
                RelayMessage.self,
                from: Data(#"{"message":"Forbidden","connectionId":"abc"}"#.utf8))
                == .foreign(message: "Forbidden"))
        #expect(
            throws: (any Error).self,
            "a message that is neither the relay's nor the gateway's is still refused"
        ) { try LinkJSON.decode(RelayMessage.self, from: Data(#"{"hello":1}"#.utf8)) }
    }

    @Test("A send says which guest it is for and which guest it came from")
    func aSendNamesTheGuestsOfTheRoom() throws {
        // The room may hold several phones and the Mac has one socket for all of them, so the
        // two ids are how a frame finds the phone it belongs to. Both are the relay's spelling.
        let golden = #"{"a":"send","d":"qw==","from":"G2","to":"G1"}"#
        let message = RelayMessage.send(payload: Data([0xAB]), to: "G1", from: "G2")
        #expect(String(decoding: try LinkJSON.encode(message), as: UTF8.self) == golden)
        #expect(try LinkJSON.decode(RelayMessage.self, from: Data(golden.utf8)) == message)
        #expect(message.from == "G2")
        // A relay that names nobody is the build before the room held several.
        #expect(RelayMessage.send(payload: Data([0xAB])).from == nil)
    }

    @Test("A peer notice says which guest moved, where the relay named one")
    func aPeerNoticeNamesTheGuest() throws {
        let message = RelayMessage.peer(event: .left, from: "G1")
        #expect(
            String(decoding: try LinkJSON.encode(message), as: UTF8.self)
                == #"{"a":"peer","event":"left","from":"G1"}"#)
        #expect(try LinkFixtures.roundTrip(message) == message)
        #expect(message.from == "G1")
        #expect(RelayMessage.peer(event: .left).from == nil)
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

    @Test("The allow-list rides in a host's join and never in a guest's")
    func onlyAHostCarriesTheAllowList() throws {
        let mac = DeviceIdentity()
        let phone = DeviceIdentity()
        let host = try RelayJoin.message(
            identity: mac, nonce: Self.nonce, room: mac.roomID, role: .host,
            allow: [phone.publicKeys.signing])
        guard case .join(_, _, _, _, let allowed, _) = host else {
            return #expect(Bool(false), "a host's join is a join")
        }
        #expect(allowed == [phone.publicKeys.signing])
        let guest = try RelayJoin.message(
            identity: phone, nonce: Self.nonce, room: mac.roomID, role: .guest,
            allow: [phone.publicKeys.signing])
        guard case .join(_, _, _, _, let none, _) = guest else {
            return #expect(Bool(false), "a guest's join is a join")
        }
        #expect(none == nil)
        #expect(!String(decoding: try LinkJSON.encode(guest), as: UTF8.self).contains("allow"))
    }

    @Test("An open room says so in the join, and a shut one says nothing at all")
    func opennessIsWrittenOnlyWhenTrue() throws {
        let mac = DeviceIdentity()
        let open = try RelayJoin.message(
            identity: mac, nonce: Self.nonce, room: mac.roomID, role: .host, open: true)
        #expect(open.isOpen)
        #expect(
            String(decoding: try LinkJSON.encode(open), as: UTF8.self).contains(#""open":true"#))
        #expect(try LinkFixtures.roundTrip(open) == open)

        let shut = try RelayJoin.message(
            identity: mac, nonce: Self.nonce, room: mac.roomID, role: .host, open: false)
        #expect(!shut.isOpen)
        #expect(!String(decoding: try LinkJSON.encode(shut), as: UTF8.self).contains("open"))
        #expect(try LinkFixtures.roundTrip(shut) == shut)
    }

    @Test("A guest cannot declare a room open, however it is asked to")
    func onlyAHostDeclaresARoomOpen() throws {
        let phone = DeviceIdentity()
        let guest = try RelayJoin.message(
            identity: phone, nonce: Self.nonce, room: DeviceIdentity().roomID, role: .guest,
            open: true)
        #expect(!guest.isOpen)
        #expect(!String(decoding: try LinkJSON.encode(guest), as: UTF8.self).contains("open"))
    }

    @Test("An allow message carries the same flag, written only when the room is open")
    func anAllowMessageCarriesOpenness() throws {
        let keys = [Data(repeating: 0x03, count: 4)]
        #expect(
            String(decoding: try LinkJSON.encode(RelayMessage.allow(pubs: keys, open: true)),
                   as: UTF8.self) == #"{"a":"allow","open":true,"pubs":["AwMDAw=="]}"#)
        #expect(
            String(decoding: try LinkJSON.encode(RelayMessage.allow(pubs: keys)), as: UTF8.self)
                == #"{"a":"allow","pubs":["AwMDAw=="]}"#)
        #expect(RelayMessage.allow(pubs: keys, open: true).isOpen)
        #expect(!RelayMessage.allow(pubs: keys).isOpen)
    }

    @Test("An allow-list longer than the relay takes is trimmed rather than refused")
    func theAllowListIsTrimmed() throws {
        let mac = DeviceIdentity()
        let keys = (0..<20).map { Data(repeating: UInt8($0), count: 32) }
        guard case .join(_, _, _, _, let allowed, _) = try RelayJoin.message(
            identity: mac, nonce: Self.nonce, room: mac.roomID, role: .host, allow: keys)
        else { return #expect(Bool(false), "a join is a join") }
        #expect(allowed?.count == RelayJoin.allowLimit)
        #expect(allowed == Array(keys.prefix(RelayJoin.allowLimit)))
    }

    @Test("The signed bytes do not change when an allow-list rides beside them")
    func theAllowListIsNotSigned() throws {
        // The relay takes the list from the connection that has just proved it holds the room's
        // key, so the signature covers the challenge and nothing else — as it did before.
        let mac = DeviceIdentity()
        guard case .join(_, _, _, let signature, _, _) = try RelayJoin.message(
            identity: mac, nonce: Self.nonce, room: mac.roomID, role: .host,
            allow: [Data(repeating: 7, count: 32)])
        else { return #expect(Bool(false), "a join is a join") }
        #expect(
            RelayJoin.verify(
                publicKey: mac.publicKeys.signing, nonce: Self.nonce, room: mac.roomID,
                role: .host, signature: signature))
    }

    @Test("A challenge is thirty-two bytes and a minute long")
    func challengeIsSized() {
        #expect(RelayJoin.nonceByteCount == 32)
        #expect(RelayJoin.challengeLifetime == 60)
    }
}
