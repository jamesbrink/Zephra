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
/// It also carries the allow-list. The relay admits a guest only when the key it signed with is
/// one this Mac has paired, so the set has to reach the relay at every join and again whenever a
/// pairing completes or is revoked — which is why `allowed` is a closure read inside an
/// observation loop rather than a list handed in once.
///
/// The wait between attempts is `LinkBackoff`, and the count resets when a guest actually
/// arrives, which is what "a live session" means for the Mac's end.
final class RelayRoad: LinkListener, @unchecked Sendable {
    private struct State {
        var isStopped = false
        var rejoining: Task<Void, Never>?
        var listener: RelayListener?
        var allow: [Data] = []
    }

    private let url: URL
    private let identity: DeviceIdentity
    /// Every paired device's raw signing key, as the host holds them right now.
    private let allowed: @MainActor () -> [Data]
    private let logger = Logger(subsystem: "io.zephra", category: "companion")
    private let stream: AsyncStream<any LinkConnection>
    private let continuation: AsyncStream<any LinkConnection>.Continuation
    private let lock = NSLock()
    private var state = State()

    /// A road into this Mac's own room on `url`, admitting the devices `allowed` names.
    init(url: URL, identity: DeviceIdentity, allowed: @escaping @MainActor () -> [Data]) {
        self.url = url
        self.identity = identity
        self.allowed = allowed
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
    /// The allow-list goes in before `start()`, so it rides in the join itself rather than as a
    /// second message the relay could admit a guest ahead of.
    private func rejoin() async {
        var attempt = 0
        while !Task.isCancelled {
            let listener = RelayListener(url: url, identity: identity)
            let keys = lock.withLock { () -> [Data] in
                state.listener = listener
                return state.allow
            }
            await listener.updateAllowList(keys)
            do {
                try await listener.start()
                for await guest in listener.connections() {
                    attempt = 0
                    continuation.yield(guest)
                }
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

    /// Reads the paired devices and re-arms itself whenever they move.
    ///
    /// The callback runs *before* the change lands, so it re-reads after a beat rather than in
    /// the callback: this is `CompanionHost`'s own observation shape, for the same reason.
    @MainActor
    private func watchAllowList() {
        guard !lock.withLock({ state.isStopped }) else { return }
        let keys = withObservationTracking { allowed() } onChange: { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                self?.watchAllowList()
            }
        }
        Task { [weak self] in await self?.publish(keys) }
    }

    /// Remembers the set the next join should carry, and tells the join that is already up.
    private func publish(_ keys: [Data]) async {
        let listener = lock.withLock { () -> RelayListener? in
            state.allow = keys
            return state.listener
        }
        await listener?.updateAllowList(keys)
    }
}
