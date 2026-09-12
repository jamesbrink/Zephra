import Foundation
import ZephraLinkProtocol

/// Which phone a frame off the one relay socket belongs to.
///
/// The whole of the routing: a session per guest the relay names, opened by whichever of the
/// guest's frame and its announcement arrives first, and ended by the `left` that names it. A
/// signal naming nobody is an older relay, which has one guest, so it lands on the one session
/// that is up.
extension RelayListener {
    /// One signal off the host's road, routed.
    func received(_ signal: RelayGuestSignal) {
        switch signal {
        case .frame(let payload, let guest):
            // A frame with no session behind it opens one: the relay's connection index is
            // eventually consistent, so a guest's first frame can beat the `peer joined` that
            // announces it, and dropping that frame would lose a handshake's hello.
            let opened = openSession(for: guest)
            if opened.isNew { continuation.yield(opened.session) }
            opened.session.deliver(payload)
        case .peer(.joined, let guest):
            let opened = openSession(for: guest)
            if opened.isNew {
                continuation.yield(opened.session)
            } else {
                logger.notice("A guest was announced over the relay after its own first frame.")
            }
        case .peer(.left, let guest):
            endSession(of: guest)
        }
    }

    /// The session one guest is on, opening one where there is none.
    ///
    /// One take of the lock rather than a read and then a write: whichever call makes the session
    /// says so, and only that one is yielded, so the host is never handed two connections for one
    /// phone.
    private func openSession(for guest: String?) -> (session: RelayGuestSession, isNew: Bool) {
        lock.withLock {
            let key = guest ?? RelayListener.anonymousGuest
            if let existing = guests[key] { return (existing, false) }
            // A relay that names nobody has one guest, so whatever session is up is that guest's.
            if guest == nil, guests.count == 1, let only = guests.values.first {
                return (only, false)
            }
            let fresh = RelayGuestSession(host: host, guest: guest)
            guests[key] = fresh
            return (fresh, true)
        }
    }

    /// One guest went. A `left` that names nobody is an older relay saying its one guest did, so
    /// it ends every session rather than guessing which.
    private func endSession(of guest: String?) {
        let ending = lock.withLock { () -> [RelayGuestSession] in
            guard let guest else {
                defer { guests = [:] }
                return Array(guests.values)
            }
            return [guests.removeValue(forKey: guest)].compactMap { $0 }
        }
        ending.forEach { $0.end(nil) }
    }

    /// Every session ended, as the road itself goes, and how many there were.
    @discardableResult
    func endEverySession(_ error: Error?) -> Int {
        let ending = lock.withLock { () -> [RelayGuestSession] in
            defer { guests = [:] }
            return Array(guests.values)
        }
        ending.forEach { $0.end(error) }
        return ending.count
    }
}
