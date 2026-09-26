import Foundation
import ZephraCore
import ZephraLinkProtocol

/// Safe interactive fixtures. These commands never open a road or touch model files.
extension LinkClient {
    func frozenWorkflow(_ command: WorkflowCommand) -> Reply {
        switch command {
        case .history:
            var seen = Set<String>()
            let rows = library.compactMap { entry -> PromptHistoryEntry? in
                guard let record = entry.record, !record.prompt.isEmpty,
                      seen.insert(record.prompt).inserted else { return nil }
                return PromptHistoryEntry(id: record.batchID ?? UUID(), prompt: record.prompt, createdAt: record.createdAt)
            }.sorted { $0.createdAt > $1.createdAt }
            return .workflow(.history(rows))
        case .storage:
            if frozenStorage == nil {
                frozenStorage = snapshot?.models.prefix(2).enumerated().map { index, model in
                    ModelStorageDTO(id: UUID(), name: model.label, detail: "Preview model files · Downloads/example--model",
                        modelIDs: [model.id], bytes: Int64(index + 1) * 2_000_000_000,
                        inUse: snapshot?.engine.loadedModelID == model.id)
                } ?? []
            }
            return .workflow(.storage(frozenStorage ?? []))
        case .download(let id):
            let label = snapshot?.models.first { $0.id == id }?.label ?? id
            snapshot?.downloads.removeAll { $0.modelID == id }
            snapshot?.downloads.append(DownloadDTO(id: id, modelID: id,
                displayName: label,
                status: .downloading, fraction: 0.35))
            return .ok
        case .pause(let id), .cancel(let id):
            if let index = snapshot?.downloads.firstIndex(where: { $0.modelID == id }) {
                snapshot?.downloads[index].status = command == .pause(id) ? .paused : .cancelled
            }
            return .ok
        case .delete(_, let token):
            frozenStorage?.removeAll { $0.id == token }
            return .ok
        case .reorder(_, let batches, let entries):
            guard snapshot?.queue.map(\.id) == entries else {
                return .error(LinkError(code: .busy, reason: "The queue changed. Try again."))
            }
            let groups = Dictionary(grouping: snapshot?.queue ?? [], by: \.batchID)
            snapshot?.queue = batches.flatMap { groups[$0] ?? [] }
            let ranks = Dictionary(uniqueKeysWithValues: batches.enumerated().map { ($0.element, $0.offset) })
            snapshot?.today.sort { (ranks[$0.id] ?? Int.max) < (ranks[$1.id] ?? Int.max) }
            return .ok
        }
    }
}
