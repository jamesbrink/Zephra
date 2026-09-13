import CryptoKit
import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraLinkTransport

@Suite("A relay invocation may finish after a later invocation")
struct RelayReorderingWindowTests {
    @Test("An 800 ms overtaking delay retains both authenticated frames on both relay ends")
    func delayedInvocation() async throws {
        let road = RelayConnection(url: URL(string: "wss://example.invalid")!,
            identity: DeviceIdentity(), room: DeviceIdentity().roomID, role: .host)
        let guest = RelayGuestSession(host: road, guest: "a-test-guest")
        #expect(guest.frameReorderingHold == road.frameReorderingHold)
        let a = SymmetricKey(size: .bits256), b = SymmetricKey(size: .bits256)
        let sender = SecureChannel(sendKey: a, receiveKey: b)
        let receiver = SecureChannel(sendKey: b, receiveKey: a)
        let inbox = OrderedInbox(channel: receiver, hold: guest.frameReorderingHold)
        let frame = Frame.envelope(Envelope(kind: .ping, body: Data("{}".utf8)))
        let first = try sender.seal(frame), second = try sender.seal(frame)
        #expect(try inbox.accept(second).isEmpty)
        try await Task.sleep(for: .milliseconds(800))
        #expect(try inbox.accept(first).count == 2)
        #expect(!receiver.isClosed)
    }
}
