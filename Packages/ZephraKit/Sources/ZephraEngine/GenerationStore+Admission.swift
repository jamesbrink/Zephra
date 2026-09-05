import ZephraCore

/// Whether anything new may begin at all.
extension GenerationStore {
    /// True when the store may take on new work: no folder is being changed, no model storage
    /// is being deleted, and the app is not quitting. The one answer every entry point reads;
    /// a caller adds only the conditions that are its own — a prompt, an idle engine, a queue.
    ///
    /// `canStopDownload` deliberately reads a narrower set: pausing a download is allowed
    /// during an image-folder change and during a deletion, since neither touches the transfer.
    public var acceptsWork: Bool {
        !isChangingModelDirectory && !isChangingImageDirectory && !isShuttingDown
            && !deletionInProgress
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
