import Foundation

extension FileStore {
    /// Registered before suspension; clear/remove invalidates even an in-flight fetch.
    func ticket(for key: String) -> UUID {
        if let ticket = generations[key] { return ticket }
        generations[key] = generation
        return generation
    }

    func changes() -> AsyncStream<Int> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { sink in
            subscribers[id] = sink
            sink.yield(revision)
            sink.onTermination = { [weak self] _ in
                Task { await self?.unsubscribe(id) }
            }
        }
    }
    private func unsubscribe(_ id: UUID) { subscribers.removeValue(forKey: id) }
    func publishChange() {
        revision &+= 1
        for sink in subscribers.values { sink.yield(revision) }
    }
}
