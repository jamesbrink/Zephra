import Foundation
import Observation
import ZephraLinkProtocol
import ZephraLinkTransport
import os

/// The relay, as one road that outlives the socket under it.
///
/// `RelayListener` is one join of one room: when the WebSocket goes — the relay's two-hour
/// connection lifetime, a sleeping Mac, a network that moved — its stream of connections
/// finishes and that listener is done. A host told to serve a new listener every time would
/// accumulate one dead listener per reconnection, so the reconnecting lives here instead: one
/// `LinkListener` the host serves once, which yields the guests of each join in turn.
///
/// It also carries the allow-list and whether the room is open. The relay admits a guest only
/// when the key it signed with is one this Mac has paired, or when the Mac has declared its room
/// open because a pairing code is on screen — so both have to reach the relay at every join and
/// again whenever either moves, which is why `allowed` and `opened` are closures read inside an
/// observation loop rather than values handed in once.
///
/// The wait between attempts is `LinkBackoff`, and the count resets when a guest actually
/// arrives, which is what "a live session" means for the Mac's end.
final class RelayRoad: LinkListener, @unchecked Sendable {
    struct State {
        var isStopped = false
        var rejoining: Task<Void, Never>?
        var listener: (any RelayJoining)?
        /// The guests of the join that is up right now, so they can be ended with it.
        var guests: [any LinkConnection] = []
        var allow: [Data] = []
        var isOpen = false
    }

    // Not private, because `RelayRoad+Rejoining` is the rest of this type: the join loop reads
    // every one of these.
    let url: URL
    let identity: DeviceIdentity
    /// Every paired device's raw signing key, as the host holds them right now.
    let allowed: @MainActor () -> [Data]
    /// Whether the room admits a guest on no list, which is true while a code is on screen.
    let opened: @MainActor () -> Bool
    /// How one join is made. Injected, so a test drives the join order without a socket.
    let join: @Sendable () -> any RelayJoining
    let logger = Logger(subsystem: "io.zephra", category: "companion")
    private let stream: AsyncStream<any LinkConnection>
    let continuation: AsyncStream<any LinkConnection>.Continuation
    /// Not private: `RelayRoad+Rejoining` is the rest of this type, and the lock is what the
    /// two halves share.
    let lock = NSLock()
    var state = State()

    /// A road into this Mac's own room on `url`, admitting the devices `allowed` names, and
    /// anybody at all while `opened` says a pairing code is up.
    init(
        url: URL, identity: DeviceIdentity, allowed: @escaping @MainActor () -> [Data],
        opened: @escaping @MainActor () -> Bool,
        join: (@Sendable () -> any RelayJoining)? = nil
    ) {
        self.url = url
        self.identity = identity
        self.allowed = allowed
        self.opened = opened
        self.join = join ?? { RelayListener(url: url, identity: identity) }
        (stream, continuation) = AsyncStream.makeStream()
    }

    /// Joins the room, and keeps rejoining it for as long as the road is open.
    ///
    /// The watch and the rejoining are two tasks on two executors, so the first join reads the
    /// allow-list for itself rather than waiting for the watch to publish one: see `rejoin()`.
    func start() {
        Task { @MainActor [weak self] in self?.watchAllowList() }
        let task = Task { [weak self] in
            guard let self else { return }
            await rejoin()
        }
        lock.withLock { state.rejoining = task }
    }

    func connections() -> AsyncStream<any LinkConnection> { stream }

    func stop() async {
        let task = lock.withLock { () -> Task<Void, Never>? in
            state.isStopped = true
            state.listener = nil
            defer { state.rejoining = nil }
            return state.rejoining
        }
        task?.cancel()
        await task?.value
        await endGuests()
        continuation.finish()
    }
}
