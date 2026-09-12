import Foundation
import ZephraLinkProtocol

/// Every local way to one Mac dialled at once, and the first to answer taken.
///
/// A phone used to dial the code's addresses one after another, ten seconds each, and a Mac
/// lists up to five — its `.local` name and four addresses, some on interfaces the phone cannot
/// see — so away from home a pairing sat at the camera for most of a minute before the relay
/// was even tried. Here every address is dialled together, a Bonjour browse dials each Mac it
/// turns up in the room as it appears, the first road to open is the one taken, and any that
/// opens after it is closed. A dial still ringing when the race is over is left to ring out on
/// its own: a Network connect does not stop when its task is cancelled, and waiting on it would
/// be the wait this exists to end.
final class LocalRoadRace: @unchecked Sendable {
    /// What the race ends with: a road, or the news that nothing will open.
    private enum Outcome {
        case opened(any LinkConnection)
        case nothingLeft
    }

    private let roads: any LinkRoads
    private let lock = NSLock()
    private var taken = false
    private var ringing = 0
    private var browsing = false
    private var dialled: Set<String> = []
    private var browser: Task<Void, Never>?
    private let stream: AsyncStream<Outcome>
    private let continuation: AsyncStream<Outcome>.Continuation

    /// A race over these roads. Nothing is dialled until `open`.
    init(roads: any LinkRoads) {
        self.roads = roads
        (stream, continuation) = AsyncStream.makeStream()
    }

    /// The first local road to open, or nil when none did inside `window`.
    ///
    /// Nil comes early where it can: every address refused and the browse finished is an answer,
    /// and only a dial still ringing or a browse still looking is worth the whole window.
    func open(endpoints: [Endpoint], room: RoomID?, window: Duration) async -> (any LinkConnection)? {
        guard !endpoints.isEmpty || room != nil else { return nil }
        for endpoint in endpoints {
            dial(endpoint.host + ":" + String(endpoint.port)) { try await self.roads.connectLAN(endpoint) }
        }
        if let room { browse(room) }
        let deadline = Task { [continuation] in
            try? await Task.sleep(for: window)
            continuation.yield(.nothingLeft)
        }
        defer {
            deadline.cancel()
            browser?.cancel()
        }
        for await outcome in stream {
            if case .opened(let road) = outcome { return road }
            return nil
        }
        return nil
    }

    /// One road dialled on a task of its own, which reports back only if it is the first to open.
    private func dial(_ id: String, _ open: @escaping @Sendable () async throws -> any LinkConnection) {
        let isNew = lock.withLock { dialled.insert(id).inserted }
        guard isNew else { return }
        lock.withLock { ringing += 1 }
        Task { [self] in
            let road = try? await open()
            let (wins, nothingLeft) = lock.withLock { () -> (Bool, Bool) in
                ringing -= 1
                if road != nil, !taken {
                    taken = true
                    return (true, false)
                }
                return (false, ringing == 0 && !browsing && !taken)
            }
            if let road {
                if wins { continuation.yield(.opened(road)) } else { await road.close() }
            } else if nothingLeft {
                continuation.yield(.nothingLeft)
            }
        }
    }

    /// The Macs Bonjour turns up in the room, each dialled as it appears.
    private func browse(_ room: RoomID) {
        lock.withLock { browsing = true }
        browser = Task { [self] in
            for await found in roads.browse() {
                for candidate in found where candidate.roomID == room {
                    dial(candidate.id) { try await self.roads.connect(candidate) }
                }
            }
            let nothingLeft = lock.withLock { () -> Bool in
                browsing = false
                return ringing == 0 && !taken
            }
            if nothingLeft { continuation.yield(.nothingLeft) }
        }
    }
}
