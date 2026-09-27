import Foundation

extension LibraryCatalog {
    /// The catalog owns cancellation even when the view that admitted work still exists.
    func request<Value: Sendable>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        guard !isClearing else { throw CancellationError() }
        try Task.checkCancellation()
        operations += 1
        let id = UUID()
        let task = Task { @MainActor in
            try Task.checkCancellation()
            let value = try await operation()
            try Task.checkCancellation()
            return value
        }
        requests[id] = { task.cancel() }
        defer { requests.removeValue(forKey: id); operations -= 1 }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    var retainedThumbnailEntries: [CachedEntry] { entries + pendingDeletions.values }
}
