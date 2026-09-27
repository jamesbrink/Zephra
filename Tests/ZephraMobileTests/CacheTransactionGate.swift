import Foundation

@MainActor final class CacheTransactionGate {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0; entered = true }
    }
    func release() { continuation?.resume(); continuation = nil }
}
