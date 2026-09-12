import Foundation
import ZephraLinkProtocol

/// Roads that never leave the process: one closure hands back an end of a
/// `MemoryLinkConnection.pair()`, and a fake Mac holds the other.
///
/// The whole point of `LinkRoads` being a protocol. A session over this is the real session —
/// the same handshake, the same sealed frames, the same dispatch — with nothing between the two
/// ends but an `AsyncStream`.
public final class MemoryLinkRoads: LinkRoads, @unchecked Sendable {
    /// How a road is opened, given which one the client asked for.
    public typealias Open = @Sendable (LinkRoad) async throws -> any LinkConnection

    private let open: Open
    private let candidates: [LinkCandidate]

    /// Roads that open through `open`, and a browse that turns up `candidates` once.
    public init(candidates: [LinkCandidate] = [], open: @escaping Open) {
        self.candidates = candidates
        self.open = open
    }

    /// Roads that go nowhere, which is what a frozen client is given.
    public static func unreachable() -> MemoryLinkRoads {
        MemoryLinkRoads { _ in throw LinkClientError.unreachable }
    }

    public func browse() -> AsyncStream<[LinkCandidate]> {
        let list = candidates
        return AsyncStream { continuation in
            if !list.isEmpty { continuation.yield(list) }
            continuation.finish()
        }
    }

    public func connect(_ candidate: LinkCandidate) async throws -> any LinkConnection {
        try await open(.lan)
    }

    public func connectLAN(_ endpoint: Endpoint) async throws -> any LinkConnection {
        try await open(.lan)
    }

    public func connectRelay(room: RoomID, pairing: Bool) async throws -> any LinkConnection {
        try await open(.relay)
    }
}
