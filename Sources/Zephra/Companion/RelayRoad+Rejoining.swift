import Foundation
import Observation
import ZephraLinkProtocol
import ZephraLinkTransport
import os

/// One join after another, and what the next one has to carry.
extension RelayRoad {
    /// Ends every guest of the join that has just gone, before the next one yields any.
    ///
    /// The socket under them is dead, and a session left over one is the failure this exists to
    /// stop: the Mac held a channel to a guest it could not answer while the phone still said
    /// "Live through relay" and every request timed out. `RelayListener` ends the session it
    /// knows about when its own road stops; this is the same rule one level up, and it holds for
    /// a listener that was replaced before it noticed.
    func endGuests() async {
        let guests = lock.withLock { () -> [any LinkConnection] in
            defer { state.guests = [] }
            return state.guests
        }
        for guest in guests { await guest.close() }
    }

    /// One join after another, with a doubling wait between failures.
    ///
    /// The allow-list and the open flag go in before `start()`, so both ride in the join itself
    /// rather than as a second message the relay could admit or refuse a guest ahead of.
    ///
    /// Which is why the first thing this does is read them. `watchAllowList()` publishes the same
    /// two values, but it is a task of its own on the main actor while this one runs on the global
    /// executor: whichever reached the state first decided what the first join carried, and when
    /// it was this one the room went up admitting **nobody** until the `allow` message landed
    /// behind it. A phone that dialled in that window was answered `not allowed` — which the phone
    /// used to read as a revocation and forget the Mac over.
    func rejoin() async {
        let known = await MainActor.run { (allow: allowed(), isOpen: opened()) }
        await publish(known.allow, open: known.isOpen)
        var attempt = 0
        while !Task.isCancelled {
            let listener = join()
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
                    lock.withLock { state.guests.append(guest) }
                    continuation.yield(guest)
                }
                logger.info("companion relay left \(self.url.absoluteString, privacy: .public)")
            } catch {
                logger.error(
                    "companion relay could not be joined: \(String(describing: error), privacy: .public)")
            }
            await listener.stop()
            await endGuests()
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
    func watchAllowList() {
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
    func publish(_ keys: [Data], open: Bool) async {
        let listener = lock.withLock { () -> (any RelayJoining)? in
            state.allow = keys
            state.isOpen = open
            return state.listener
        }
        await listener?.updateAllowList(keys, open: open)
    }
}
