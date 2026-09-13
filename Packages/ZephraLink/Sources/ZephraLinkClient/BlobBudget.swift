import Foundation

/// Bounds announced bytes across clients, including unsolicited transfers.
@MainActor
public final class BlobBudget {
    private var held: [UUID: [UUID: Int]] = [:]
    public let limit: Int
    public let fileLimit: Int
    public init(limit: Int = 268_435_456, fileLimit: Int = 134_217_728) {
        self.limit = limit; self.fileLimit = fileLimit
    }
    func reserve(owner: UUID, blob: UUID, bytes: Int) -> Bool {
        guard bytes >= 0, bytes <= fileLimit else { return false }
        let existing = held[owner]?[blob] ?? 0
        let total = held.values.reduce(0) { $0 + $1.values.reduce(0, +) }
        guard bytes <= limit - total + existing else { return false }
        held[owner, default: [:]][blob] = bytes
        return true
    }
    func release(owner: UUID, blob: UUID) { held[owner]?[blob] = nil }
    func release(owner: UUID) { held[owner] = nil }
}
