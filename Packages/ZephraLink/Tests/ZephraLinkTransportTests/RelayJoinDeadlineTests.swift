import Foundation
import Testing
import ZephraLinkProtocol
import ZephraLinkTransport

/// A relay road dialled at an address that answers nothing, and how long `start()` takes to say so.
@Suite("A relay join that gets no answer fails inside the join deadline")
struct RelayJoinDeadlineTests {
    @Test("a black-hole address fails the join inside the deadline, not the socket's own timeout")
    func blackHoleFailsInsideTheDeadline() async {
        // 10.255.255.1 is unrouted from here: the TCP connect never completes.
        let road = RelayConnection(
            url: URL(string: "wss://10.255.255.1")!, identity: DeviceIdentity(),
            room: DeviceIdentity().roomID, role: .guest, joinDeadline: .seconds(1))
        let clock = ContinuousClock()
        let started = clock.now
        var failure: (any Error)?
        do { try await road.start() } catch { failure = error }
        let took = clock.now - started
        print("relay start() against a black hole took \(took): \(String(describing: failure))")
        #expect(failure != nil)
        // The socket's own timeout is sixty seconds; the first shape of the deadline, a sleeper
        // racing the join in a task group, waited that long, since the group waited for a
        // receive that task cancellation does not stop.
        #expect(took < .seconds(4), "took \(took)")
    }
}
