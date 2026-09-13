import Foundation

/// Global transfer concurrency with one active transfer per client and cancellation-aware waiters.
@MainActor
public final class TransferAdmission {
    private struct Waiting {
        let id: UUID
        let owner: UUID
        let priority: TransferPriority
        let queuedAt: Int
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var active: Set<UUID> = []
    private var waiting: [Waiting] = []
    private let limit: Int
    private var grants = 0
    var waitingCount: Int { waiting.count }
    public init(limit: Int = 2) { self.limit = max(1, limit) }
    func enter(_ owner: UUID, priority: TransferPriority = .background) async throws {
        try Task.checkCancellation()
        if active.count < limit && !active.contains(owner) { active.insert(owner); grants += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting.append(Waiting(id: id, owner: owner, priority: priority, queuedAt: grants, continuation: continuation))
            }
        } onCancel: { Task { @MainActor in self.cancel(id) } }
        if Task.isCancelled { leave(owner); throw CancellationError() }
    }
    func leave(_ owner: UUID) {
        active.remove(owner)
        while active.count < limit, let index = nextIndex {
            let next = waiting.remove(at: index)
            active.insert(next.owner)
            grants += 1
            next.continuation.resume()
        }
    }
    /// Never interrupt a sealed transfer. FIFO breaks ties; aging bounds starvation.
    private var nextIndex: Int? {
        let eligible = waiting.indices.filter { !active.contains(waiting[$0].owner) }
        if let aged = eligible.first(where: { grants - waiting[$0].queuedAt >= 8 }) { return aged }
        return eligible.max { left, right in
            let a = waiting[left].priority.rawValue, b = waiting[right].priority.rawValue
            return a == b ? left > right : a < b
        }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
