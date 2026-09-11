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
    private struct State {
        var isStopped = false
        var rejoining: Task<Void, Never>?
        var listener: RelayListener?
        var allow: [Data] = []
        var isOpen = false
    }

    private let url: URL
    private let identity: DeviceIdentity
    /// Every paired device's raw signing key, as the host holds them right now.
    private let allowed: @MainActor () -> [Data]
    /// Whether the room admits a guest on no list, which is true while a code is on screen.
    private let opened: @MainActor () -> Bool
    private let logger = Logger(subsystem: "io.zephra", category: "companion")
    private let stream: AsyncStream<any LinkConnection>
    private let continuation: AsyncStream<any LinkConnection>.Continuation
    private let lock = NSLock()
    private var state = State()

    /// A road into this Mac's own room on `url`, admitting the devices `allowed` names, and
    /// anybody at all while `opened` says a pairing code is up.
    init(
        url: URL, identity: DeviceIdentity, allowed: @escaping @MainActor () -> [Data],
        opened: @escaping @MainActor () -> Bool
    ) {
        self.url = url
        self.identity = identity
        self.allowed = allowed
        self.opened = opened
        (stream, continuation) = AsyncStream.makeStream()
    }

    /// Joins the room, and keeps rejoining it for as long as the road is open.
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
        continuation.finish()
    }

    /// One join after another, with a doubling wait between failures.
    ///
    /// The allow-list and the open flag go in before `start()`, so both ride in the join itself
    /// rather than as a second message the relay could admit or refuse a guest ahead of.
    private func rejoin() async {
        var attempt = 0
        while !Task.isCancelled {
            let listener = RelayListener(url: url, identity: identity)
            let room = lock.withLock { () -> (allow: [Data], isOpen: Bool) in
                state.listener = listener
                return (state.allow, state.isOpen)
            }
            await listener.updateAllowList(room.allow, open: room.isOpen)
            do {
                try await listener.start()
                // At info, and on both edges. A relay join is the one piece of this road that
                // fails silently from the outside: the Mac looks exactly the same whether it is
                // sitting in its room waiting or has never reached the relay at all.
                logger.info("companion relay joined \(self.url.absoluteString, privacy: .public)")
                for await guest in listener.connections() {
                    attempt = 0
                    continuation.yield(guest)
                }
                logger.info("companion relay left \(self.url.absoluteString, privacy: .public)")
            } catch {
                logger.notice("companion relay could not be joined: \(error.localizedDescription, privacy: .public)")
            }
            await listener.stop()
            lock.withLock { state.listener = nil }
            guard !Task.isCancelled else { break }
            attempt += 1
            try? await Task.sleep(for: LinkBackoff.delay(after: attempt))
        }
    }

    /// Reads the paired devices and whether a code is up, and re-arms itself whenever either
    /// moves. Both are read inside the one tracking closure, so a code going up republishes for
    /// the same reason a pairing completing does.
    ///
    /// The callback runs *before* the change lands, so it re-reads after a beat rather than in
    /// the callback: this is `CompanionHost`'s own observation shape, for the same reason.
    @MainActor
    private func watchAllowList() {
        guard !lock.withLock({ state.isStopped }) else { return }
        let room = withObservationTracking {
            (allow: allowed(), isOpen: opened())
        } onChange: { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                self?.watchAllowList()
            }
        }
        Task { [weak self] in await self?.publish(room.allow, open: room.isOpen) }
    }

    /// Remembers what the next join should carry, and tells the join that is already up.
    private func publish(_ keys: [Data], open: Bool) async {
        let listener = lock.withLock { () -> RelayListener? in
            state.allow = keys
            state.isOpen = open
            return state.listener
        }
        await listener?.updateAllowList(keys, open: open)
    }
}
