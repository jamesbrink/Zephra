import Foundation
import ZephraCore

extension ModelTransfers {
    func fetch(
        _ id: UUID, _ model: ModelDescriptor, _ locations: ModelLocations, release: URL?,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        guard let claim = claims[id], case .huggingFace(let repo, _, _) = model.source else {
            throw BackendError.modelNotAvailable(model.fullName)
        }
        try Task.checkCancellation()
        try ModelDirectoryAccess.prepare(locations.root)
        let missing = Set(locations.missingAdapters(of: model).map(\.repoID))
        let parts = claim.parts.filter { ($0.repoID == repo && release == nil) || missing.contains($0.repoID) }
        // Preflight every dependency before starting any of this model's bodies. The task
        // is registered before suspension, so compatible requests share even revision lookup.
        for part in parts {
            let entry = repository(part)
            entry.listeners[id] = onProgress
            guard let preparation = entry.preparation else { continue }
            entry.work = try await TaskReceipt().value(of: preparation)
            try Task.checkCancellation()
        }
        let tally = TransferProgress(parts: parts, emit: onProgress)
        for part in parts {
            let entry = repository(part)
            entry.listeners[id] = { event in tally.update(part, event) }
            if let progress = entry.progress { tally.update(part, progress) }
            if !order.contains(part), entry.result == nil, entry.task == nil { order.append(part) }
        }
        schedule()
        for part in parts { try await wait(for: part, owner: id) }
        try Task.checkCancellation()
        return release ?? locations.downloads(repoID: repo)
    }

    func repository(_ part: RepositoryDownload) -> RepositoryTransfer {
        if let entry = transfers[part] { return entry }
        let entry = RepositoryTransfer(part)
        entry.owners = Set(claims.filter { $0.value.parts.contains(part) }.keys)
        let downloader = downloader
        entry.preparation = Task {
            let session = downloader.makeSession()
            defer { session.invalidateAndCancel() }
            return try await DownloadRetry.run(
                isPermanent: { ($0 as? ModelDownloadError)?.isPermanent ?? false }, onRetry: { _, _ in }
            ) { try await downloader.listing(of: [part], on: session) }
        }
        transfers[part] = entry
        return entry
    }

    func wait(for part: RepositoryDownload, owner: UUID) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard let entry = transfers[part], entry.owners.contains(owner) else {
                    continuation.resume(throwing: CancellationError()); return
                }
                if let result = entry.result { continuation.resume(with: result) }
                else { entry.waiters[owner] = continuation }
            }
        } onCancel: { Task { await self.cancelWait(part, owner) } }
        try Task.checkCancellation()
    }

    private func cancelWait(_ part: RepositoryDownload, _ owner: UUID) {
        transfers[part]?.waiters.removeValue(forKey: owner)?.resume(throwing: CancellationError())
    }
}
