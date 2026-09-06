import Foundation
import ZephraCore

extension ModelTransfers {
    /// The pool's `ModelDownloader.fetchPrebuilt`: the variant's one part goes through the
    /// same preflight, lane and space reservation as a release, shared with any other request
    /// for the same model, and is renamed into place by whichever owner is still waiting when
    /// it lands. Nil whenever it could not be had — not published, host down, transfer broken
    /// past its retries, no room — so the backend builds it instead and nobody sees the mirror.
    func fetchPrebuilt(
        _ id: UUID, _ model: ModelDescriptor, _ locations: ModelLocations,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL? {
        guard let claim = claims[id],
              let part = claim.parts.first(where: { if case .mirror = $0.origin { return true } else { return false } })
        else { return nil }
        try Task.checkCancellation()
        try ModelDirectoryAccess.prepare(locations.root)
        let entry = repository(part)
        entry.listeners[id] = onProgress
        do {
            if let preparation = entry.preparation {
                entry.work = try await TaskReceipt().value(of: preparation)
            }
            try Task.checkCancellation()
            if !order.contains(part), entry.result == nil, entry.task == nil { order.append(part) }
            schedule()
            try await wait(for: part, owner: id)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        try Task.checkCancellation()
        let built = locations.built(model)
        // Another owner may have published it a moment ago; the partial is then already gone.
        if !FileManager.default.fileExists(atPath: part.destination.path(percentEncoded: false)) {
            return built
        }
        return try ModelDownloader.publishPrebuilt(part.destination, as: built)
    }
}
