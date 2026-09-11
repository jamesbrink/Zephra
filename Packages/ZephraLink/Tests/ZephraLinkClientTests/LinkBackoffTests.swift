import Foundation
import Testing
import ZephraLinkClient

/// How long the phone waits before it tries the Mac again.
@Suite("The wait between attempts doubles and stops")
struct LinkBackoffTests {
    @Test("the first four waits are a second, two, four and eight")
    func theWaitsDouble() {
        #expect(LinkBackoff.delay(after: 1) == .seconds(1))
        #expect(LinkBackoff.delay(after: 2) == .seconds(2))
        #expect(LinkBackoff.delay(after: 3) == .seconds(4))
        #expect(LinkBackoff.delay(after: 4) == .seconds(8))
    }

    @Test("it stops at half a minute, however long the Mac stays away")
    func theWaitIsCapped() {
        #expect(LinkBackoff.delay(after: 8) == LinkBackoff.cap)
        #expect(LinkBackoff.delay(after: 400) == LinkBackoff.cap)
    }
}
