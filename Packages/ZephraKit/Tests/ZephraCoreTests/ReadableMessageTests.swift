import Foundation
import Testing

@testable import ZephraCore

@Suite("readableMessage")
struct ReadableMessageTests {
    private enum Silent: Error { case weightsMissing }

    @Test("a system error gives its own sentence, and a silent Swift error its case name")
    func systemErrorsSpeakAndSilentOnesAreNamed() {
        #expect(CocoaError(.fileNoSuchFile).readableMessage == "The file doesn’t exist.")
        #expect(
            URLError(.networkConnectionLost).readableMessage
                == URLError(.networkConnectionLost).localizedDescription)
        #expect(Silent.weightsMissing.readableMessage == "weightsMissing")
    }
}
