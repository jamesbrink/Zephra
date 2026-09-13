import Foundation
import ZephraCore
import ZephraLinkProtocol

/// One comparison per `StateDelta` case: what the Mac shows now against what the phones were
/// last told, and a message for each thing that differs.
///
/// Deliberately not a diff of one big value. Each case is published on its own, so a step
/// counter ticking does not resend the model list and a favourite toggled does not resend the
/// queue — which is the whole reason the protocol has a dozen delta cases rather than one.
extension CompanionHost {
    /// Where the engine is, and whether the Mac is taking work at all.
    func publishEngine() {
        let engine = EngineStateProjection.engine(store)
        if engine != published.engine {
            published.engine = engine
            broadcast(.engine(engine))
        }
        let accepts = store.acceptsWork
        if accepts != published.acceptsWork {
            published.acceptsWork = accepts
            broadcast(.acceptsWork(accepts))
        }
    }

    /// What is waiting, what is running, and today's runs, which are made out of both.
    func publishQueue() {
        let queue = QueuedEntryProjection.entries(store.queue)
        if queue != published.queue {
            published.queue = queue
            broadcast(.queue(queue))
        }
        let running = QueuedEntryProjection.running(store.running)
        if running != published.running {
            published.running = running
            broadcast(.running(running))
        }
        let today = RunSummaryProjection.runs(
            items: index.items, history: store.history, queue: store.queue, running: store.running)
        if today != published.today {
            published.today = today
            broadcast(.today(today))
        }
    }

    /// Pictures this session has made, as one message each.
    ///
    /// A row that has *changed* counts as well as one that has arrived, which is why the record
    /// kept is the rows and not their ids: a picture is inserted with no file name and is given
    /// one a moment later when its write lands, and that is the only thing the phone's canvas
    /// needs to fetch the picture. `historyInserted` is already an upsert at the far end, so
    /// sending the row again is how a change is said.
    ///
    /// Insertions go out oldest first so a phone applying them ends with the same order the Mac
    /// holds, which is newest first. Everything from the deepest row that moved up to the newest
    /// goes, not only the rows that differ: each one is re-inserted at the front, so re-sending
    /// the rows in front of a changed one is what puts them back in front of it.
    func publishHistory() {
        let entries = HistoryEntryProjection.entries(store.history)
        guard entries != published.history else { return }
        let before = Dictionary(published.history.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Set(entries.map(\.id))
        for entry in published.history where !after.contains(entry.id) {
            broadcast(.historyRemoved(entry.id))
        }
        if let deepest = entries.lastIndex(where: { before[$0.id] != $0 }) {
            for entry in entries[...deepest].reversed() {
                broadcast(.historyInserted(entry))
            }
        }
        published.history = entries
    }

    /// The model in force, the survey of what is on disk, and the transfers in flight.
    func publishModels() {
        let modelID = store.descriptor.id
        if modelID != published.modelID {
            published.modelID = modelID
            broadcast(.model(ModelSummary(store.descriptor)))
        }
        let availability = AvailabilityProjection.availability(store.availability)
        if availability != published.availability {
            published.availability = availability
            broadcast(.availability(availability))
        }
        let downloads = DownloadProjection.downloads(store.downloads.items)
        if downloads != published.downloads {
            published.downloads = downloads
            broadcast(.downloads(downloads))
        }
    }

    /// What changed in the library folder, by fingerprint.
    ///
    /// Nothing is published on the first pass. The snapshot a session opens with carries the
    /// folder's `libraryCount` and not the folder, and the phone reads the entries across for
    /// itself, a page at a time, as soon as that snapshot lands
    /// (`LinkClient.startLibraryPull`). A reset here on the first pass would be a hundred
    /// entries the phone is already asking for, and would say nothing about the rest.
    func publishLibrary() {
        let items = LibraryEntryProjection.listing(index.items)
        let versions = items.reduce(into: [String: String]()) { map, item in
            map[item.fileName] = LibraryEntry.version(
                fileName: item.fileName, contentModifiedAt: item.contentModifiedAt,
                fileSize: Int(item.fileSize))
        }
        defer { published.libraryVersions = versions }
        guard published.hasPublished, versions != published.libraryVersions else { return }
        let changed = items.filter { published.libraryVersions[$0.fileName] != versions[$0.fileName] }
        let removed = published.libraryVersions.keys.filter { versions[$0] == nil }.sorted()
        guard changed.count + removed.count <= CompanionPublication.resetThreshold else {
            let page = LibraryEntryProjection.page(
                items, offset: 0, limit: CompanionPublication.resetThreshold)
            return broadcast(.library(.reset(page.entries, total: items.count)))
        }
        if !removed.isEmpty { broadcast(.library(.removed(removed))) }
        if !changed.isEmpty {
            broadcast(.library(.upserted(changed.map(LibraryEntryProjection.entry))))
        }
    }

    /// The newest frame of the run in flight, at most ten a second, encoded off the main actor.
    func publishPreview() {
        guard let preview = store.livePreview else {
            published.previewFingerprint = nil
            return
        }
        let fingerprint = Self.fingerprint(of: preview)
        guard fingerprint != published.previewFingerprint else { return }
        let now = ContinuousClock.now
        if let sent = published.previewSentAt,
           now - sent < .seconds(1 / Self.previewsPerSecond) { return }
        published.previewFingerprint = fingerprint
        published.previewSentAt = now
        guard !isSeeding else { return }
        let engine = published.engine ?? EngineStateDTO(store.state)
        Task { @MainActor [weak self] in
            let frame = await Task.detached(priority: .utility) {
                PreviewEncoder.frame(preview, step: engine.step ?? 0, steps: engine.steps ?? 0)
            }.value
            guard let self, let frame else { return }
            for session in sessions where session.wantsPreviews { session.send(frame) }
        }
    }

    /// Enough of a frame to tell it from the one before without hashing the whole buffer: a
    /// preview is a quarter of a megabyte and these arrive several times a second.
    private static func fingerprint(of preview: GenerationPreview) -> Data {
        var bytes = Data()
        withUnsafeBytes(of: Int64(preview.width)) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: Int64(preview.height)) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: Int64(preview.pixels.count)) { bytes.append(contentsOf: $0) }
        bytes.append(preview.pixels.prefix(16))
        bytes.append(preview.pixels.suffix(16))
        return bytes
    }
}
