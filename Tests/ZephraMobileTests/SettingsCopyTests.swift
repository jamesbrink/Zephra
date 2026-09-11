import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

@testable import ZephraMobile

/// What the settings surface says, which is the one place in the app where a state becomes a
/// word rather than a picture.
///
/// `MobileKeychain` is deliberately not here: a keychain item needs a keychain access group,
/// and a unit-test bundle hosted in the simulator's app has no entitlements to put one in, so
/// every call answers `errSecMissingEntitlement` and a suite over it would be a suite over that.
/// It is exercised by running the app.
@Suite("The settings surface says where things stand")
struct SettingsCopyTests {
    @Test("Every connection state has a word, and a failure keeps the Mac's own sentence")
    func namesEveryState() {
        #expect(ConnectionRow.words(for: .offline) == "Offline")
        #expect(ConnectionRow.words(for: .searching) == "Searching")
        #expect(ConnectionRow.words(for: .connecting(.lan)) == "Connecting")
        #expect(ConnectionRow.words(for: .handshaking(.relay)) == "Connecting")
        #expect(ConnectionRow.words(for: .live(.lan)) == "Live on local network")
        #expect(ConnectionRow.words(for: .live(.relay)) == "Live through relay")
        #expect(ConnectionRow.words(for: .failed("halcyon is asleep.")) == "halcyon is asleep.")
    }

    @Test("The version is the bundle's two numbers, in the Mac's order")
    func readsTheBuildFromTheBundle() {
        #expect(AboutRow.version.hasPrefix("0.1.0"))
    }

    @Test("This end's own failures get sentences too")
    func namesTheClientsOwnFailures() {
        #expect(PairingEntry.message(for: LinkClientError.timedOut).contains("did not answer"))
        #expect(PairingEntry.message(for: LinkClientError.unreachable).contains("could not reach"))
        #expect(PairingEntry.message(for: LinkClientError.notPaired).contains("not paired"))
    }

    @Test("A pairing that failed says what the client wrote, not what was thrown")
    func prefersTheClientsSentence() {
        let written = PairingEntry.message(
            for: LinkClientError.unreachable, connection: .failed("Zephra could not reach halcyon."))
        #expect(written == "Zephra could not reach halcyon.")
    }

    @Test("With nothing on the connection to go on, the error's own sentence stands")
    func fallsBackToTheError() {
        let refusal = LinkError(code: .refused, reason: "That pairing code has expired.")
        #expect(PairingEntry.message(for: refusal, connection: .offline) == refusal.reason)
    }
}
