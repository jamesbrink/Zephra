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
            current = image
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
    /// Does nothing while the engine cannot take work, for the same reason `generate()` does
    /// nothing unless `canQueue`: draining during a download, a load or a warm-up would swap
    /// models under the load that is already running and cancel it. The prompt tested is the
    /// record's rather than the one in the field, because that is the one about to run.
    public func queueVariation(of item: LibraryItem) {
        guard let record = item.provenance.record,
              record.settings().isReadyToGenerate,
              state.acceptsGeneration || isDraining
        else { return }
        let known = ModelCatalog.descriptor(id: record.modelID)
        let model = known ?? descriptor
        var request = record.settings(referenceImage: item.referenceImage).withRandomSeed()
        if known == nil { request = request.onSchedule(of: model) }
        request = model.capabilities.clamp(request)
        descriptor = model
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
