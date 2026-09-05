import Foundation
import ZephraCore

extension ModelTransfers {
    func schedule() {
        let first = order.filter { part in preferred.map { transfers[part]?.owners.contains($0) == true } ?? false }
        let pending = first + order.filter { !first.contains($0) }
        for part in pending where active < limit {
            guard let entry = transfers[part], entry.task == nil, entry.result == nil,
                  !entry.owners.isEmpty, let work = entry.work else { continue }
            let downloader = downloader
            do { try reserveSpace(entry, work: work) }
            catch { finish(part, .failure(error)); continue }
            active += 1
            entry.task = Task {
                let result: Result<Void, any Error>
                do {
                    let session = downloader.makeSession()
                    defer { session.invalidateAndCancel() }
                    try await DownloadRetry.run(
                        isPermanent: { ($0 as? ModelDownloadError)?.isPermanent ?? false }, onRetry: { _, _ in }
                    ) {
                        try await downloader.downloadPrepared(work, on: session) { event in
                            Task { await self.report(part, event) }
                        }
                    }
                    result = .success(())
                } catch { result = .failure(error) }
                self.active -= 1
                self.finish(part, result)
                self.schedule()
            }
        }
    }

    private func report(_ part: RepositoryDownload, _ event: DownloadProgressEvent) {
        guard let entry = transfers[part], entry.result == nil else { return }
        entry.progress = event
        if let total = event.totalBytes, let done = event.completedBytes {
            entry.remainingBytes = max(0, total - done)
        }
        for listener in entry.listeners.values { listener(event) }
    }

    private func finish(_ part: RepositoryDownload, _ result: Result<Void, any Error>) {
        guard let entry = transfers[part] else { return }
        entry.result = result
        entry.remainingBytes = 0
        for waiter in entry.waiters.values { waiter.resume(with: result) }
        entry.waiters.removeAll()
    }

    /// Reserve unique outstanding bytes on this volume; the packer separately checks its
    /// output before building. Capacity is queried again for every admitted transfer.
    private func reserveSpace(
        _ entry: RepositoryTransfer, work: [(part: RepositoryDownload, files: [RepositoryFile])]
    ) throws {
        let url = entry.part.destination
        let volume = try capacity(url)
        let needed = work.reduce(Int64(0)) { total, item in
            total + item.files.reduce(0) { $0 + max(0, $1.bytes - downloader.bytesOnDisk(of: $1, in: item.part.destination)) }
        }
        let reserved = reservedBytes(on: volume.id)
        if let free = volume.available, free < needed + reserved + (256 << 20) {
            throw BackendError.downloadFailed("Not enough space for the active downloads. Free space, then Retry.")
        }
        entry.volume = volume.id
        entry.remainingBytes = needed
    }
}
