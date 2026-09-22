import Foundation
import ZephraCore

/// Shared repository ownership and a bounded network lane, independent of inference.
/// Reservations are all-or-none, so crossed repository dependencies cannot deadlock.
public actor ModelTransfers {
    let downloader: ModelDownloader
    let limit: Int
    let capacity: @Sendable (URL) throws -> TransferCapacity
    var builds: [UUID: (volume: String, bytes: Int64)] = [:]
    var claims: [UUID: TransferClaim] = [:]
    var waiting: [(UUID, TransferClaim, CheckedContinuation<Void, any Error>)] = []
    var transfers: [RepositoryDownload: RepositoryTransfer] = [:]
    var order: [RepositoryDownload] = []
    var preferred: UUID?
    var active = 0
    var releasing: Set<UUID> = []

    public init(downloader: ModelDownloader = ModelDownloader(), limit: Int = 2,
                capacity: @escaping @Sendable (URL) throws -> TransferCapacity = TransferCapacity.read) {
        self.capacity = capacity
        self.downloader = downloader
        self.limit = max(1, limit)
    }

    public func reserve(_ id: UUID, model: ModelDescriptor, locations: ModelLocations) async throws {
        try Task.checkCancellation()
        let claim = try TransferClaim(model, locations)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting.append((id, claim, continuation))
                admit()
            }
        } onCancel: { Task { await self.cancelReservation(id) } }
        try Task.checkCancellation()
    }

    public func prioritize(_ id: UUID) { preferred = id }

    func admit() {
        var remaining: [(UUID, TransferClaim, CheckedContinuation<Void, any Error>)] = []
        for (id, claim, continuation) in waiting {
            if claims.contains(where: { key, value in
                claim.conflicts(with: value) || (releasing.contains(key) && claim.parts.contains { part in
                    value.parts.contains { TransferClaim.path($0.destination) == TransferClaim.path(part.destination) }
                })
            }) {
                remaining.append((id, claim, continuation))
            } else {
                claims[id] = claim
                for part in claim.parts { transfers[part]?.owners.insert(id) }
                continuation.resume()
            }
        }
        waiting = remaining
    }

    func cancelReservation(_ id: UUID) {
        if let index = waiting.firstIndex(where: { $0.0 == id }) {
            waiting.remove(at: index).2.resume(throwing: CancellationError())
        }
    }

    /// Stops only unshared writers and waits for their handles before cleanup or read release.
    /// Claims remain live throughout settlement, so a new conflicting request cannot race it.
    public func release(_ id: UUID, discard: Bool = false) async throws {
        cancelReservation(id)
        guard let claim = claims[id] else { return }
        releasing.insert(id)
        let owned = transfers.values.filter { $0.owners.contains(id) }
        var stopped: [RepositoryTransfer] = []
        for entry in owned {
            entry.owners.remove(id)
            entry.listeners.removeValue(forKey: id)
            entry.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            if entry.owners.isEmpty {
                entry.preparation?.cancel()
                entry.task?.cancel()
                stopped.append(entry)
            }
        }
        for entry in stopped {
            _ = await entry.preparation?.result
            await entry.task?.value
            // Nobody can have joined while cancellation settled: `admit()` refuses any claim
            // on a destination in `releasing`. Were one kept here with its cancelled task and
            // preparation, that joiner would be stranded on work that never finishes.
            assert(entry.owners.isEmpty, "a claim cannot be admitted onto a part being released")
            transfers.removeValue(forKey: entry.part)
            order.removeAll { $0 == entry.part }
        }
        var cleanupError: (any Error)?
        if discard {
            let unshared = claim.parts.filter { part in
                !claims.contains { other, value in
                    other != id && value.parts.contains { TransferClaim.path($0.destination) == TransferClaim.path(part.destination) }
                }
            }
            do { try ModelDownloader.discardUnfinished(unshared, under: claim.root) }
            catch { cleanupError = error }
        }
        builds.removeValue(forKey: id)
        claims.removeValue(forKey: id)
        releasing.remove(id)
        admit()
        schedule()
        if let cleanupError { throw cleanupError }
    }
}
