import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraLinkClient

/// Roads whose every address behaves as the test says: answers after a delay, or refuses.
private final class ScriptedRoads: LinkRoads, @unchecked Sendable {
    enum Answer: Sendable {
        case opens(after: Duration)
        case refuses
    }

    private let lock = NSLock()
    private var script: [String: Answer]
    private let found: [LinkCandidate]
    private(set) var opened: [MemoryLinkConnection] = []

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

    func connectRelay(room: RoomID) async throws -> any LinkConnection {
        throw LinkClientError.unreachable
    }

    private func answer(_ key: String) async throws -> any LinkConnection {
        guard case .opens(let delay) = lock.withLock({ script[key] }) ?? .refuses else {
            throw LinkClientError.unreachable
        }
        try await Task.sleep(for: delay)
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
        let roads = ScriptedRoads(script: [
            "slow": .opens(after: .milliseconds(200)),
            "quick": .opens(after: .milliseconds(10)),
        ])
        let started = ContinuousClock.now
        let road = await LocalRoadRace(roads: roads).open(
            endpoints: [Endpoint(host: "slow", port: 1), Endpoint(host: "quick", port: 1)],
            room: nil, window: .seconds(3))
        #expect(road != nil)
        #expect(ContinuousClock.now - started < .milliseconds(150))
        try await Task.sleep(for: .milliseconds(300))
        #expect(roads.stillOpen == 1)
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
        #expect(roads.opened.count == 1)
    }

    @Test("nothing to dial is nil at once")
    func nothingToDial() async {
        let road = await LocalRoadRace(roads: ScriptedRoads(script: [:])).open(
            endpoints: [], room: nil, window: .seconds(3))
        #expect(road == nil)
    }
}
