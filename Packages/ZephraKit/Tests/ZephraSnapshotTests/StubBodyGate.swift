import Foundation
import Synchronization

/// Holds body replies without blocking URLProtocol's callback thread or relying on delays.
final class StubBodyGate: Sendable {
    private struct State {
        var opened = false
        var pending: [@Sendable () -> Void] = []
    }
    private let state = Mutex(State())

    func submit(_ reply: @escaping @Sendable () -> Void) {
        let immediate = state.withLock { value in
            if value.opened { return true }
            value.pending.append(reply)
            return false
        }
        if immediate { reply() }
    }

    func open() {
        let pending = state.withLock { value in
            value.opened = true
            let pending = value.pending
            value.pending.removeAll()
            return pending
        }
        for reply in pending { reply() }
    }
}
