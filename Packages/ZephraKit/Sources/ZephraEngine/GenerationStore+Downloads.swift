import Foundation
import ZephraCore
import ZephraSnapshot

extension GenerationStore {
    /// Narrower than `acceptsWork` on purpose: pausing a download is allowed during an
    /// image-folder change and during a deletion, since neither touches the transfer.
    public func canStopDownload(_ modelID: String) -> Bool {
        !isChangingModelDirectory && !isShuttingDown && !isStoppingPreparation
            && !queue.contains { $0.model.id == modelID } && running?.model.id != modelID
            && loadedDescriptor?.id != modelID
    }

    public func pauseDownload(_ modelID: String, discard: Bool = false) {
        guard canStopDownload(modelID) else { return }
        if preparingModel?.id == modelID || (isSwappingModel && descriptor.id == modelID) {
            stopPreparation(discard: discard)
        } else {
            Task { await downloads.stop(modelID, discard: discard) }
        }
    }

    public func resumeDownload(_ model: ModelDescriptor) {
        guard acceptsWork, let registry else { return }
        if model.id == descriptor.id, !isDraining, !isUpscaling, !isSwappingModel, !isStoppingPreparation {
            retry()
        } else { _ = downloads.start(model, registry: registry, locations: locations) }
    }

    func stopPreparation(discard: Bool) {
        let modelID = preparingModel?.id ?? descriptor.id
        let pendingLoad = bootstrapTask
        let pendingSwitch = switchTask
        loadIdentity = nil
        preparingModel = nil
        queue.removeAll()
        isSwitchingForQueue = false
        isStoppingPreparation = true
        transition(to: .cancelling)
        pendingLoad?.cancel()
        pendingSwitch?.cancel()
        stopTask = Task {
            await downloads.stop(modelID, discard: discard)
            await pendingSwitch?.value
            await pendingLoad?.value
            await unloadModel()
            isSwappingModel = false
            isStoppingPreparation = false
            transition(to: .idle)
        }
    }

    /// Called before app termination. File handles and heavyweight operations settle first.
    public func shutdown() async {
        isShuttingDown = true
        downloads.admissionClosed = true
        loadIdentity = nil
        queue.removeAll()
        switchTask?.cancel()
        bootstrapTask?.cancel()
        generationTask?.cancel()
        upscaleTask?.cancel()
        await storageSettlement?.wait()
        await downloads.pauseAll()
        await settle()
        await unloadModel()
    }

    public func modelStorageIsInUse(_ item: ModelStorageItem) -> Bool {
        if !acceptsWork { return true }
        if let loadedDirectory {
            let parent = item.url.resolvingSymlinksInPath().standardizedFileURL.path
            let child = loadedDirectory.resolvingSymlinksInPath().standardizedFileURL.path
            if child == parent || child.hasPrefix(parent + "/") { return true }
        }
        var ids = downloads.protectedModelIDs
        ids.formUnion(queue.map { $0.model.id })
        if let running { ids.insert(running.model.id) }
        if let preparingModel { ids.insert(preparingModel.id) }
        return !ids.isDisjoint(with: item.modelIDs)
    }

    public func deleteModelStorage(_ item: ModelStorageItem, inventory: ModelInventory) async {
        guard !modelStorageIsInUse(item) else { return }
        let settlement = StorageSettlement()
        storageSettlement = settlement
        deletionInProgress = true
        defer {
            deletionInProgress = false
            Task { await settlement.finish() }
            // A queued entry whose predecessor finished during the deletion found `drain()`
            // closed; the same hand-back an upscale makes on its way out.
            if state == .ready { drain() }
        }
        await inventory.delete(item)
        await refreshAvailability()
    }
}
