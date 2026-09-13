import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraLinkClient

/// Roads whose every address behaves as the test says: answers after a delay, or refuses.
private final class ScriptedRoads: LinkRoads, @unchecked Sendable {
    enum Answer: Sendable {
        case opens(after: Duration)
        case held(DelayedRoad)
        case refuses
    }

    private let lock = NSLock()
    private var script: [String: Answer]
    private let found: [LinkCandidate]
    private var opened: [MemoryLinkConnection] = []
    var openedCount: Int { lock.withLock { opened.count } }

    init(script: [String: Answer], found: [LinkCandidate] = []) {
        self.script = script
        self.found = found
    }

    /// The roads this handed out that are still open.
    var stillOpen: Int { lock.withLock { opened.filter(\.isOpen).count } }

    func browse() -> AsyncStream<[LinkCandidate]> {
        let list = found
        return AsyncStream { continuation in
            if !list.isEmpty { continuation.yield(list) }
            continuation.finish()
        }
    }

    func connect(_ candidate: LinkCandidate) async throws -> any LinkConnection {
        try await answer(candidate.id)
    }

    func connectLAN(_ endpoint: Endpoint) async throws -> any LinkConnection {
        try await answer(endpoint.host)
    }

    func connectRelay(room: RoomID, pairing: Bool) async throws -> any LinkConnection {
        throw LinkClientError.unreachable
    }

    private func answer(_ key: String) async throws -> any LinkConnection {
        switch lock.withLock({ script[key] }) ?? .refuses {
        case .opens(let delay): try await Task.sleep(for: delay)
        case .held(let gate): await gate.wait()
        case .refuses: throw LinkClientError.unreachable
        }
        let (road, _) = MemoryLinkConnection.pair()
        lock.withLock { opened.append(road) }
        return road
    }
}

@Suite("Dialling every local road at once")
struct LocalRoadRaceTests {
    private let room = DeviceIdentity().roomID

    @Test("the first address to answer is the road, and the one that answers later is closed")
    func firstToAnswerWins() async throws {
        let gate = DelayedRoad()
        let roads = ScriptedRoads(script: [
            "slow": .held(gate),
            "quick": .opens(after: .milliseconds(10)),
        ])
        let road = await LocalRoadRace(roads: roads).open(
            endpoints: [Endpoint(host: "slow", port: 1), Endpoint(host: "quick", port: 1)],
            room: nil, window: .seconds(3))
        #expect(road != nil)
        #expect(roads.openedCount == 1, "the winner returns before the blocked address is released")
        await gate.open()
        let deadline = ContinuousClock.now + .seconds(2)
        while (roads.openedCount < 2 || roads.stillOpen != 1) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(roads.openedCount == 2)
        #expect(roads.stillOpen == 1)
    }

    @Test("Cancellation and timeout close a road that opens after the race ended", arguments: [false, true])
    func abandonedRoad(_ cancel: Bool) async throws {
        let gate = DelayedRoad()
        let roads = ScriptedRoads(script: ["held": .held(gate)])
        let attempt = Task {
            await LocalRoadRace(roads: roads).open(endpoints: [Endpoint(host: "held", port: 1)],
                room: nil, window: cancel ? .seconds(30) : .milliseconds(20))
        }
        if cancel { attempt.cancel() }
        #expect(await attempt.value == nil)
        await gate.open()
        let deadline = ContinuousClock.now + .seconds(3)
        while (roads.openedCount != 1 || roads.stillOpen != 0) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(roads.openedCount == 1)
        #expect(roads.stillOpen == 0)
    }

    @Test("every address refusing is answered at once, not after the window")
    func allRefuse() async {
        let roads = ScriptedRoads(script: [:])
        let started = ContinuousClock.now
        let road = await LocalRoadRace(roads: roads).open(
            endpoints: [Endpoint(host: "a", port: 1), Endpoint(host: "b", port: 1)],
            room: nil, window: .seconds(3))
        #expect(road == nil)
        #expect(ContinuousClock.now - started < .milliseconds(500))
    }

    @Test("an address still ringing at the window's end is given up on")
    func ringsOut() async {
        let roads = ScriptedRoads(script: ["far": .opens(after: .seconds(5))])
        let started = ContinuousClock.now
        let road = await LocalRoadRace(roads: roads).open(
            endpoints: [Endpoint(host: "far", port: 1)], room: nil, window: .milliseconds(100))
        #expect(road == nil)
        let took = ContinuousClock.now - started
        #expect(took >= .milliseconds(100) && took < .seconds(1))
    }

    @Test("a Mac Bonjour turns up in the room is dialled, and one in another room is not")
    func bonjourInTheRoom() async {
        let other = DeviceIdentity().roomID
        let roads = ScriptedRoads(
            script: ["here": .opens(after: .milliseconds(10)), "elsewhere": .opens(after: .zero)],
            found: [
                LinkCandidate(id: "elsewhere", name: "Other", roomID: other),
                LinkCandidate(id: "here", name: "Mine", roomID: room),
            ])
        let road = await LocalRoadRace(roads: roads).open(endpoints: [], room: room, window: .seconds(3))
        #expect(road != nil)
        #expect(roads.openedCount == 1)
    }

    @Test("nothing to dial is nil at once")
    func nothingToDial() async {
        let road = await LocalRoadRace(roads: ScriptedRoads(script: [:])).open(
            endpoints: [], room: nil, window: .seconds(3))
        #expect(road == nil)
    }
}

/// A provider that returns even after cancellation, so the losing road must be closed.
private actor DelayedRoad {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
