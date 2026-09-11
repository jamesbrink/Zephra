import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraMobile

@Suite("Reading a pairing code")
struct PairingEntryTests {
    /// When the fixture's code stops being accepted.
    ///
    /// A whole number of seconds, deliberately. A pairing payload writes its date as seconds
    /// since 1970 to keep the code small, and Foundation counts from 2001, so a date with a
    /// fraction in it comes back a few nanoseconds out and two payloads that are the same
    /// payload compare unequal. Every date here is on the second, and the clock is stated
    /// rather than read, so the suite says the same thing on every run.
    private let expiry = Date(timeIntervalSince1970: 1_789_040_400)

    /// A payload for a Mac called `halcyon`, good until `expiry`.
    private func payload() -> PairingPayload {
        PairingPayload(
            hostName: "halcyon",
            keys: DeviceIdentity().publicKeys,
            endpoints: [Endpoint(host: "192.168.1.20", port: 52_311)],
            secret: Data(repeating: 7, count: PairingSecret.byteCount),
            expiresAt: expiry)
    }

    @Test("A scanned link is the payload it encodes")
    func readsWholeLink() throws {
        let original = payload()
        let link = try PairingURL.encode(original).absoluteString
        #expect(try PairingEntry.parse(link, at: expiry - 60) == original)
    }

    @Test("The bare payload is read without the link round it")
    func readsBarePayload() throws {
        let original = payload()
        let link = try PairingURL.encode(original)
        let bare = try #require(
            URLComponents(url: link, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "d" })?.value)
        #expect(try PairingEntry.parse(bare, at: expiry - 60) == original)
    }

    @Test("Whitespace round a pasted code is ignored")
    func trimsWhitespace() throws {
        let original = payload()
        let link = try PairingURL.encode(original).absoluteString
        #expect(try PairingEntry.parse("\n  \(link)\t ", at: expiry - 60) == original)
    }

    @Test("A code that is only just alive is still read")
    func acceptsCodeAboutToExpire() throws {
        let original = payload()
        let link = try PairingURL.encode(original).absoluteString
        #expect(try PairingEntry.parse(link, at: expiry - 1) == original)
    }

    @Test("A code past its time is refused where the person can be told")
    func refusesExpired() throws {
        let link = try PairingURL.encode(payload()).absoluteString
        #expect(throws: LinkError.self) { try PairingEntry.parse(link, at: expiry) }
        do {
            _ = try PairingEntry.parse(link, at: expiry)
            Issue.record("an expired code was accepted")
        } catch {
            #expect(PairingEntry.message(for: error).contains("expired"))
        }
    }

    @Test("Anything that is not a code says so, in words", arguments: [
        "", "hello", "https://example.com/pair?d=abc", "zephra://pair?v=1", "zephra://pair?d=!!",
    ])
    func refusesGarbage(text: String) {
        do {
            _ = try PairingEntry.parse(text)
            Issue.record("\(text.debugDescription) was read as a pairing code")
        } catch {
            #expect(PairingEntry.message(for: error) == PairingEntry.notACode.reason)
        }
    }

    @Test("An error nobody wrote a sentence for still gets one")
    func describesAnyError() {
        struct Nameless: Error {}
        #expect(PairingEntry.message(for: Nameless()) == "That pairing code could not be read.")
    }
}
