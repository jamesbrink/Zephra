import ZephraCore

/// Whether anything new may begin at all.
extension GenerationStore {
    /// True when the store may take on new work: no folder is being changed, no model storage
    /// is being deleted, the GPU is still answering, and the app is not quitting. The one
    /// answer every entry point reads; a caller adds only the conditions that are its own —
    /// a prompt, an idle engine, a queue.
    ///
    /// `deviceLost` is here rather than at each door because every door leads to the same
    /// place: a command buffer the driver has already said it will not run. Closing admission
    /// in one line is what greys Generate, Load, Unload and Upscale together and refuses a
    /// paired phone in the same sentence (`GenerationStore+DeviceLoss`).
    ///
    /// `canStopDownload` deliberately reads a narrower set: pausing a download is allowed
    /// during an image-folder change and during a deletion, since neither touches the transfer.
    public var acceptsWork: Bool {
        !isChangingModelDirectory && !isChangingImageDirectory && !isShuttingDown
            && !deletionInProgress && !deviceLost
    }

    /// Whether this Mac may choose `model` at all: whether it can hold it some way, held
    /// whole, with the decode tiled, or read from disk every step.
    ///
    /// The gate behind every door a model is chosen through — the menu, a picture's own model,
    /// the fallback at launch and a paired device's request. A model that cannot be held is
    /// never loaded and never downloaded: a 16 GB mini asked for one on 2026-09-13 and the app
    /// was aborted by Metal rather than failing in a way anything could catch.
    public func canSelect(_ model: ModelDescriptor) -> Bool {
        ModelCatalog.fit(model, budget: memoryBudget).isSelectable
    }

    /// Whether this model could be got into memory right now, starting from nothing if need be.
    ///
    /// The half of admission that is not about the engine standing ready: a Mac with nothing
    /// loaded, or one whose last run the GPU lost, will still take a generation — the queue's
    /// own `drain()` loads what the entry needs before it runs it. Without this a phone against
    /// a Mac that had a device fault saw `canQueue: false` for the rest of the session, with no
    /// way back but the Mac's own keyboard.
    public func canLoad(_ model: ModelDescriptor) -> Bool {
        switch state {
        case .idle, .failed: break
        // Ready over another model's weights is a swap, which is what Load promises there —
        // "Unloads X first" — and what a paired phone's `loadModel` asks for. `loadModel()`
        // alone makes it; `startLoading` still refuses `.ready`.
        case .ready where isSwapFromReady(to: model): break
        default: return false
        }
        return acceptsWork && !isSwappingModel && !isStoppingPreparation && !isUpscaling
            && canSelect(model) && availability[model.id]?.isObtainable != false
    }

    /// Whether a load of `model` from `.ready` is a swap off another model's weights with the
    /// queue empty: the one case `.ready` still has a load to make.
    func isSwapFromReady(to model: ModelDescriptor) -> Bool {
        guard let loaded = loadedDescriptor, loaded.id != model.id else { return false }
        return queue.isEmpty && !isDraining
    }

    /// Whether a variation of `item` can be queued: the store takes work, the engine is ready
    /// or already working down the queue, and the record it would run has a prompt.
    ///
    /// Unlike `canQueue` this does not wait for a reference picture still on its way into the
    /// well: a variation replaces the settings outright, picture included, so the read is
    /// cancelled by `queueVariation` the way `select(_:)` cancels it, rather than waited for.
    public func canQueueVariation(of item: LibraryItem) -> Bool {
        guard acceptsWork, state.acceptsGeneration || isDraining,
            let record = item.provenance.record
        else { return false }
        return record.settings().isReadyToGenerate
    }
}
