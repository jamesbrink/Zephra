import Testing

@testable import ZephraMobile

/// What the canvas puts where a run's first frame will go.
@Suite("The run's rectangle says what is actually happening")
struct RunPlaceholderTests {
    @Test("with the Mac in reach it is the Mac's own word for the phase")
    func showsThePhase() {
        #expect(RunPlaceholderView.headline(phase: "Denoising", isLive: true) == "Denoising")
        #expect(RunPlaceholderView.headline(phase: nil, isLive: true) == "Starting")
        #expect(RunPlaceholderView.note(isLive: true).contains("after the first step"))
    }

    @Test("with the Mac out of reach it says so rather than repeating a stale phase")
    func saysReconnecting() {
        #expect(RunPlaceholderView.headline(phase: "Denoising", isLive: false) == "Reconnecting")
        #expect(RunPlaceholderView.headline(phase: nil, isLive: false) == "Reconnecting")
        #expect(RunPlaceholderView.note(isLive: false) == "The run carries on at your Mac.")
    }
}
