import Foundation
import ZephraCore

/// What the library pane asks the store to do: put an image on the canvas, or make another one
/// like it. The store never reads the library; the library hands it one item at a time.
extension GenerationStore {
    /// Shows a library image on the canvas, reading its bytes off the main actor.
    ///
    /// Unlike `select(_:)` this does not adopt the image's settings. Opening something to look
    /// at it should not quietly replace the prompt being written; the settings come across only
    /// when a variation is asked for, which is an explicit act. A second open supersedes the
    /// first, so clicking down a row of thumbnails does not queue up a row of reads.
    public func open(_ item: LibraryItem) async {
        await show(item) { store, image in store.current = image }
    }

    /// Shows a library image on the canvas *and* adopts its settings, the way `select(_:)` does
    /// for a picture this session made: what the canvas sidebar's wall does, where every square
    /// is a run to pick up again — the prompt, the size, the seed and the picture it was edited
    /// from land in the capsule, so the obvious next move is to tweak one thing and generate.
    ///
    /// The settings are adopted when the bytes arrive, not when the square is clicked, because
    /// they are read out of the file with the picture; a click on the running card or another
    /// square in between cancels the read and nothing is adopted.
    public func select(_ item: LibraryItem) async {
        await show(item) { store, image in store.select(image) }
    }

    /// The read behind `open(_:)` and `select(_:)`: off the main actor, superseding any read
    /// still in flight, and publishing through `publish` when the bytes are back.
    private func show(
        _ item: LibraryItem,
        publish: @escaping @MainActor (GenerationStore, GeneratedImage) -> Void
    ) async {
        guard !isChangingImageDirectory else { return }
        // Looking at something else is what stops the canvas following the run. Said here
        // rather than when the bytes arrive, so a slow read does not leave the run's frames
        // playing under a picture that is on its way.
        stopFollowingRun()
        openTask?.cancel()
        let task = Task { [weak self] in
            let opened = await Self.read(item)
            guard !Task.isCancelled, let self else { return }
            guard let image = opened else {
                lastLibraryFailure = LibraryFailure(
                    itemID: item.id, action: .open, reason: "It could not be read.")
                return
            }
            lastLibraryFailure = nil
            publish(self, image)
        }
        openTask = task
        await task.value
    }

    /// Queues another image from the same request, with a fresh seed.
    ///
    /// The model comes from the record when the catalog still knows it, so a variation of an
    /// image made by another model swaps models rather than rendering the same prompt on the
    /// wrong one. When it does not — a model this build has dropped — the current model takes
    /// the request on its own schedule, because steps and guidance do not mean the same thing
    /// to two families.
    ///
    /// `settings` and `descriptor` follow, so the controls show what is about to run.
    ///
    /// Does nothing unless `canQueueVariation(of:)`, for the same reason `generate()` does
    /// nothing unless `canQueue`: draining during a download, a load or a warm-up would swap
    /// models under the load that is already running and cancel it. The prompt tested is the
    /// record's rather than the one in the field, because that is the one about to run.
    public func queueVariation(of item: LibraryItem) {
        guard canQueueVariation(of: item), let record = item.provenance.record else { return }
        let known = ModelCatalog.descriptor(id: record.modelID)
        let model = known ?? descriptor
        var request = record.settings(referenceImage: item.referenceImage).withRandomSeed()
        if known == nil { request = request.onSchedule(of: model) }
        request = model.capabilities.clamp(request)
        // A variation is a request for an image, the same as pressing Generate, so the canvas
        // follows it: without this an image asked for while an older picture was open would
        // finish invisibly.
        startFollowingRun()
        // The request carries the record's own reference, or none; a library read still on
        // its way was for the settings being replaced, as in `select(_:)`.
        _ = claimReference()
        descriptor = model
        modelAwaitsGenerate = false
        settings = request
        queue.append(QueuedGeneration(model: model, settings: request))
        if isDraining {
            logger.info("queued a variation, \(self.queue.count) waiting")
        } else {
            drain()
        }
    }

    /// The image behind one library item, or nil when the file has gone or carries no record.
    private static func read(_ item: LibraryItem) async -> GeneratedImage? {
        await Task.detached(priority: .utility) { () -> GeneratedImage? in
            guard let data = try? Data(contentsOf: item.url),
                  let record = GenerationRecord.read(from: data)
            else { return nil }
            return record.image(
                pngData: data, fileURL: item.url,
                referenceImage: GenerationRecord.reference(in: data))
        }.value
    }
}
