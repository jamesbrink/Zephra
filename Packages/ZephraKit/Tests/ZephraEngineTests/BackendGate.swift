/// A deliberate non-cooperative backend suspension: tests decide exactly when work settles.
actor BackendGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    private(set) var entered = false

    func wait() async {
        entered = true
        guard !opened else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
