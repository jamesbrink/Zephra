import Foundation
import Synchronization
import Testing
import ZephraLinkProtocol

@testable import Zephra

/// What the Mac's relay road carries into a room, and when.
@MainActor
@Suite("The relay road joins with the allow-list in hand")
struct RelayRoadTests {
    /// A join that never opens a socket, and remembers what it was told before it was made.
    private nonisolated final class Join: RelayJoining, Sendable {
        private let state = Mutex(State())
        private let guests: AsyncStream<any LinkConnection>
        private let continuation: AsyncStream<any LinkConnection>.Continuation

        init() {
            (guests, continuation) = AsyncStream.makeStream()
        }

        func updateAllowList(_ keys: [Data], open: Bool) async {
            state.withLock { $0.told.append((keys, open)) }
        }

        func start() async throws {
            state.withLock { $0.atJoin = $0.told.last }
        }

        func connections() -> AsyncStream<any LinkConnection> { guests }

        func stop() async { continuation.finish() }

        /// What the room admitted at the moment the join was made, or nil before there was one.
        var atJoin: (allow: [Data], open: Bool)? {
            state.withLock { $0.atJoin.map { (allow: $0.0, open: $0.1) } }
        }

        private struct State {
            var told: [([Data], Bool)] = []
            var atJoin: ([Data], Bool)?
        }
    }

    /// A road over one such join, with one paired key and a code on screen.
    private func road(admitting key: Data, over join: Join) -> RelayRoad {
        RelayRoad(
            url: URL(string: "wss://relay.example")!, identity: DeviceIdentity(),
            allowed: { [key] }, opened: { true }, join: { join })
    }

    @Test("the first join carries the paired keys, not an empty list the allow message fills in")
    func theFirstJoinCarriesThePairedKeys() async throws {
        let key = Data(repeating: 3, count: 32)
        let join = Join()
        let road = road(admitting: key, over: join)

        road.start()
        for _ in 0..<200 where join.atJoin == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let admitted = try #require(join.atJoin, "the road never joined the room")

        // A join carrying `allow: []` is a room that admits nobody, and the phone that dialled
        // before the `allow` message landed was answered `not allowed`.
        #expect(admitted.allow == [key])
        #expect(admitted.open)
        await road.stop()
    }
}
