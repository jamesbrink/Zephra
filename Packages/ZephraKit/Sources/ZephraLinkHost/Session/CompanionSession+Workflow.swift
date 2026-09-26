import Foundation
import ZephraCore
import ZephraEngine
import ZephraLinkProtocol

extension CompanionSession {
    func performWorkflow(_ command: WorkflowCommand, on host: CompanionHost) async throws -> Reply {
        switch command {
        case .history:
            host.store.promptHistory.seed(host.index.items)
            return .workflow(.history(host.store.promptHistory.entries))
        case .storage:
            let inventory = host.makeModelInventory()
            await inventory.refresh()
            guard inventory.modelsDirectory == host.store.modelStorageRoot else { throw LinkError(code: .busy, reason: "This Mac is busy. Try again in a moment.") }
            // Keep tokens stable across refreshes only while the exact directory still exists.
            let current = inventory.items
            storageTokens = storageTokens.filter { _, token in
                token.root == host.store.modelStorageRoot && current.contains(where: {
                    $0.id == token.itemID && StorageToken.identity($0.url) == token.identity
                })
            }
            let rows = current.map { item in
                let existing = storageTokens.first { $0.value.itemID == item.id }?.key
                let id = existing ?? UUID()
                storageTokens[id] = StorageToken(itemID: item.id, url: item.url, root: inventory.modelsDirectory)
                let kind = item.kind == .built ? "Built" : (item.isComplete ? "Downloaded" : "Partial download")
                let shared = item.modelIDs.count > 1 ? " · Shared by \(item.modelIDs.count) models" : ""
                return ModelStorageDTO(id: id, name: item.name, detail: kind + shared + " · " + item.location,
                    modelIDs: item.modelIDs, bytes: item.bytes, inUse: host.store.modelStorageIsInUse(item))
            }
            return .workflow(.storage(rows))
        case .reorder(let id, let batches, let entries):
            if let answer = workflowResults[id] { return answer }
            let answer: Reply = host.store.reorderQueue(batches: batches, expectedEntries: entries) ? .ok :
                .error(LinkError(code: .busy, reason: "The queue changed. Refresh it and try again."))
            rememberWorkflow(answer, id: id)
            return answer
        case .download(let id):
            let model = try Self.model(id)
            guard host.store.acceptsWork else { throw LinkError(code: .busy, reason: "This Mac is busy. Try again in a moment.") }
            host.store.downloadModel(model)
            return .ok
        case .pause(let id), .cancel(let id):
            _ = try Self.model(id)
            guard host.store.canStopDownload(id) else {
                throw LinkError(code: .busy, reason: "This model is in use. Finish its jobs before stopping the download.")
            }
            if case .cancel = command { host.store.pauseDownload(id, discard: true) }
            else { host.store.pauseDownload(id) }
            return .ok
        case .delete(let id, let token):
            if let answer = workflowResults[id] { return answer }
            let answer: Reply
            do { try await deleteStorage(token, on: host); answer = .ok }
            catch let error as LinkError { answer = .error(error) }
            catch { answer = .error(LinkError(code: .badRequest, reason: error.localizedDescription)) }
            rememberWorkflow(answer, id: id)
            return answer
        }
    }

    private func deleteStorage(_ id: UUID, on host: CompanionHost) async throws {
        guard let token = storageTokens[id], !token.identity.isEmpty,
              token.root == host.store.modelStorageRoot,
              StorageToken.identity(token.url) == token.identity else {
            throw LinkError(code: .notFound, reason: "This model folder changed. Refresh Models and try again.")
        }
        let inventory = host.makeModelInventory()
        await inventory.refresh()
        guard token.root == host.store.modelStorageRoot,
              let item = inventory.items.first(where: { $0.id == token.itemID }),
              StorageToken.identity(item.url) == token.identity else { throw LinkError(code: .busy, reason: "This Mac is busy. Try again in a moment.") }
        guard !host.store.modelStorageIsInUse(item) else {
            throw LinkError(code: .busy, reason: "This model is in use. Unload it and finish its queued jobs before deleting it.")
        }
        await host.store.deleteModelStorage(item, inventory: inventory)
        if let failure = inventory.lastFailure { throw LinkError(code: .badRequest, reason: failure) }
        guard !FileManager.default.fileExists(atPath: item.url.path) else { throw LinkError(code: .busy, reason: "This Mac is busy. Try again in a moment.") }
        storageTokens.removeValue(forKey: id)
    }

    private func rememberWorkflow(_ answer: Reply, id: UUID) {
        workflowResults[id] = answer; workflowOrder.append(id)
        while workflowOrder.count > 64 { workflowResults.removeValue(forKey: workflowOrder.removeFirst()) }
    }
}
