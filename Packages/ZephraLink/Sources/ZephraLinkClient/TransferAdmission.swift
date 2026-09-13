import Foundation

/// Global transfer concurrency with one active transfer per client and cancellation-aware waiters.
@MainActor
public final class TransferAdmission {
    private struct Waiting {
        let id: UUID
        let owner: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var active: Set<UUID> = []
    private var waiting: [Waiting] = []
    private let limit: Int
    public init(limit: Int = 2) { self.limit = max(1, limit) }
    func enter(_ owner: UUID) async throws {
        try Task.checkCancellation()
        if active.count < limit && !active.contains(owner) { active.insert(owner); return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting.append(Waiting(id: id, owner: owner, continuation: continuation))
            }
        } onCancel: { Task { @MainActor in self.cancel(id) } }
        if Task.isCancelled { leave(owner); throw CancellationError() }
    }
    func leave(_ owner: UUID) {
        active.remove(owner)
        while active.count < limit, let index = waiting.firstIndex(where: { !active.contains($0.owner) }) {
            let next = waiting.remove(at: index)
            active.insert(next.owner)
            next.continuation.resume()
        }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
