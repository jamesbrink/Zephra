import Foundation
import ZephraCore

extension ModelDownloads {
    func stop(_ modelID: String, discard: Bool) async {
        guard var request = requests[modelID] else { return }
        if request.released {
            guard discard else { return }
            request = DownloadRequest(request.model, request.locations)
            request.discard = true
            request.stopped = .cancelled
            requests[modelID] = request
            retained[request.id] = request
            let cleanup = request
            request.task = Task {
                do {
                    try await transfers.reserve(cleanup.id, model: cleanup.model, locations: cleanup.locations)
                    cleanup.settled = true
                    await releaseIfUnused(cleanup)
                    return cleanup.locations.root
                } catch {
                    cleanup.settled = true
                    await releaseIfUnused(cleanup)
                    throw error
                }
            }
            publish(request, .cancelled)
            _ = await request.task?.result
            return
        }
        request.discard = discard
        request.stopped = discard ? .cancelled : .paused
        publish(request, discard ? .cancelled : .paused)
        request.task?.cancel()
        _ = await request.task?.result
        await releaseIfUnused(request)
    }

    func pauseAll() async {
        admissionClosed = true
        let pending = Array(retained.values)
        for request in pending where !request.settled {
            request.stopped = .paused
            request.task?.cancel()
        }
        for request in pending { _ = await request.task?.result }
    }

    /// Requests remain protected while cancellation and file closure settle.
    var protectedModelIDs: Set<String> { Set(retained.values.map { $0.model.id }) }

    public func status(for modelID: String) -> String? {
        guard let row = items.first(where: { $0.id == modelID }) else { return nil }
        switch row.status {
        case .queued: return "Download queued"
        case .downloading: return "Downloading \(Int((row.progress?.fraction ?? 0) * 100))%"
        case .paused: return "Download paused"
        case .failed: return "Download failed"
        case .cancelled, .completed: return nil
        }
    }

    public func sharesActiveTransfer(_ model: ModelDescriptor) -> Bool {
        let repositories = Set(model.adapters.map(\.repoID) + [model.sourceName])
        return items.contains { row in
            guard row.id != model.id, row.status == .downloading || row.status == .queued else { return false }
            return !repositories.isDisjoint(with: Set(row.model.adapters.map(\.repoID) + [row.model.sourceName]))
        }
    }
}
