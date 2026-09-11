import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("An envelope carries a body it does not have to understand")
struct EnvelopeTests {
    @Test("A body encoded into an envelope decodes back out of it")
    func bodyRoundTrips() throws {
        let start = BlobStart(byteCount: 4096, mime: "image/png")
        let envelope = try Envelope.encoding(start, kind: .blobStart)
        #expect(try envelope.decode(BlobStart.self) == start)
        #expect(envelope.inReplyTo == nil)
    }

    @Test("A message this build does not know is still a well-formed envelope")
    func unknownKindsStayReadable() throws {
        let json = #"{"body":"e30=","id":"3A7B9C10-2D4E-4F6A-8B5C-1E9D0A2B3C4D","kind":"ping"}"#
        let envelope = try LinkJSON.decode(Envelope.self, from: Data(json.utf8))
        #expect(envelope.kind == .ping)
        #expect(envelope.body == Data("{}".utf8))
    }

    @Test("Every message kind writes and reads as its own name")
    func kindsRoundTrip() throws {
        for kind in MessageKind.allCases {
            #expect(try LinkFixtures.roundTrip(kind) == kind)
        }
    }

    @Test("Every refusal code writes and reads as its own name")
    func errorCodesRoundTrip() throws {
        for code in LinkErrorCode.allCases {
            let error = LinkError(code: code, reason: "because")
            #expect(try LinkFixtures.roundTrip(error) == error)
        }
    }

    @Test("The same value encodes to the same bytes twice, which the handshake depends on")
    func encodingIsStable() throws {
        let hello = Hello(
            ephemeral: Data(count: 32), keys: DeviceIdentity().publicKeys, nonce: Data(count: 16),
            pairing: true, deviceName: "Test Phone")
        #expect(try LinkJSON.encode(hello) == LinkJSON.encode(hello))
        #expect(
            try LinkJSON.encode(LinkJSON.decode(Hello.self, from: LinkJSON.encode(hello)))
                == LinkJSON.encode(hello))
    }
}
