import Testing
import ZephraLinkClient

@testable import ZephraMobile

@Suite("The pairing screen says which road it is on")
struct PairingProgressTests {
    @Test("every busy state has a line, and neither idle state does")
    func linesForStates() {
        #expect(PairingProgress.words(for: .searching) == "Looking for your Mac nearby…")
        #expect(PairingProgress.words(for: .connecting(.lan)) == "Connecting over the local network…")
        #expect(PairingProgress.words(for: .connecting(.relay)) == "Reaching your Mac through the secure relay…")
        #expect(PairingProgress.words(for: .handshaking(.relay)) == "Pairing…")
        #expect(PairingProgress.words(for: .live(.lan)) == "Paired")
        #expect(PairingProgress.words(for: .offline) == nil)
        #expect(PairingProgress.words(for: .failed("no")) == nil)
    }
}
