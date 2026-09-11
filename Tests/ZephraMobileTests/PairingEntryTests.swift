import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraMobile

@Suite("Reading a pairing code")
struct PairingEntryTests {
    /// A payload for a Mac called `halcyon`, good until `expiresAt`.
    private func payload(expiresAt: Date) -> PairingPayload {
        PairingPayload(
            hostName: "halcyon",
            keys: DeviceIdentity().publicKeys,
            endpoints: [Endpoint(host: "192.168.1.20", port: 52_311)],
            secret: Data(repeating: 7, count: PairingSecret.byteCount),
            expiresAt: expiresAt)
    }

    @Test("A scanned link is the payload it encodes")
    func readsWholeLink() throws {
        let original = payload(expiresAt: Date().addingTimeInterval(60))
        let link = try PairingURL.encode(original).absoluteString
        #expect(try PairingEntry.parse(link) == original)
    }

    @Test("The bare payload is read without the link round it")
    func readsBarePayload() throws {
        let original = payload(expiresAt: Date().addingTimeInterval(60))
        let link = try PairingURL.encode(original)
        let bare = try #require(
            URLComponents(url: link, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "d" })?.value)
        #expect(try PairingEntry.parse(bare) == original)
    }

    @Test("Whitespace round a pasted code is ignored")
    func trimsWhitespace() throws {
        let original = payload(expiresAt: Date().addingTimeInterval(60))
        let link = try PairingURL.encode(original).absoluteString
        #expect(try PairingEntry.parse("\n  \(link)\t ") == original)
    }

    @Test("A code past its time is refused where the person can be told")
    func refusesExpired() throws {
        let stale = payload(expiresAt: Date().addingTimeInterval(-1))
        let link = try PairingURL.encode(stale).absoluteString
        #expect(throws: LinkError.self) { try PairingEntry.parse(link) }
        do {
            _ = try PairingEntry.parse(link)
            Issue.record("an expired code was accepted")
        } catch {
            #expect(PairingEntry.message(for: error).contains("expired"))
        }
    }

    @Test("A code that is only just alive is still read")
    func acceptsCodeAboutToExpire() throws {
        let moment = Date()
        let original = payload(expiresAt: moment.addingTimeInterval(1))
        let link = try PairingURL.encode(original).absoluteString
        #expect(try PairingEntry.parse(link, at: moment) == original)
    }

    @Test("Anything that is not a code says so", arguments: [
        "", "hello", "https://example.com/pair?d=abc", "zephra://pair?v=1",
    ])
    func refusesGarbage(text: String) {
        #expect(throws: LinkError.self) { try PairingEntry.parse(text) }
    }

    @Test("An error nobody wrote a sentence for still gets one")
    func describesAnyError() {
        struct Nameless: Error {}
        #expect(PairingEntry.message(for: Nameless()) == "That pairing code could not be read.")
    }
}
