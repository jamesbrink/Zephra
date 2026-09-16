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
        // Retry is the load itself, and only while nothing is loaded: with another model up
        // and this one merely chosen, a retry would answer ready and resume nothing.
        if model.id == descriptor.id, loadedDescriptor == nil, !isDraining, !isUpscaling,
            !isSwappingModel, !isStoppingPreparation
        {
            retry()
        } else { _ = downloads.start(model, registry: registry, locations: locations) }
    }

    /// Fetches `model`'s files and stops there, whatever is chosen and whatever is loaded.
    ///
    /// What the model browser's Download button presses. `resumeDownload` is the same request
    /// asked about the chosen model, and answers it with a load where it can; this one never
    /// loads anything, so a person can queue a download while a run they care about is going.
    public func downloadModel(_ model: ModelDescriptor) {
        guard acceptsWork, let registry else { return }
        _ = downloads.start(model, registry: registry, locations: locations)
    }

    func stopPreparation(discard: Bool) {
        let modelID = preparingModel?.id ?? descriptor.id
        let pendingLoad = bootstrapTask
        let pendingSwitch = switchTask
        loadIdentity = nil
        preparingModel = nil
        // A stop must not leave a forced residency behind for whatever loads next.
        residencyOverride = nil
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
            await releaseModel()
            // A swap asked for after this stop began owns the flag; only the swap this stop
            // cancelled gives it up. Clearing it outright opened a window in which a retry
            // could start a load under the pending swap.
            isSwappingModel = switchTask.map { !$0.isCancelled } ?? false
            isStoppingPreparation = false
            transition(to: .idle)
        }
    }

    /// Called before app termination. File handles and heavyweight operations settle first.
    public func shutdown() async {
        isShuttingDown = true
        downloads.admissionClosed = true
        // The idle clock holds this store for as long as its wait lasts, which is up to an hour.
        idleTask?.cancel()
        idleTask = nil
        loadIdentity = nil
        queue.removeAll()
        switchTask?.cancel()
        bootstrapTask?.cancel()
        generationTask?.cancel()
        upscaleTask?.cancel()
        await storageSettlement?.wait()
        await downloads.pauseAll()
        await settle()
        // Not over a lost GPU. `releaseModel` unloads on the inference actor, which drops the
        // backend's arrays, synchronizes Metal and hands the allocator's cache back — three
        // more command buffers submitted into a channel the driver is refusing, on the way out
        // of a process that is about to end anyway. The weights go back when it does.
        guard !deviceLost else { return }
        await releaseModel()
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
