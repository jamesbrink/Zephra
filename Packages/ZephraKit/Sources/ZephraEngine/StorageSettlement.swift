/// Quit waits for the entire storage transaction, including its final bookkeeping.
/// Waiting is deliberately non-cancellable: task cancellation cannot close file handles.
actor StorageSettlement {
    private var finished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !finished else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish() {
        finished = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}
