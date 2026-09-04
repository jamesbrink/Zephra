import Foundation
import ZephraCore

/// Several seeds of one prompt from one press of Generate, and the two questions the interface
/// asks about the run in progress: what it has produced, and how much of it is still to come.
extension GenerationStore {
    /// The most seeds one press of Generate may queue. Eight of a twenty-second model is
    /// already a coffee; more than that belongs in a script, not a button.
    public static let batchLimit = 8

    /// Queues `count` seeds of the current settings on the current model, and starts the first
    /// at once if nothing else is running. `count` is clamped to 1...`batchLimit`.
    ///
    /// The first keeps whatever seed is in the field, so a batch of four is a superset of the
    /// single image the same press would otherwise have made.
    public func generate(count: Int) {
        guard canQueue else { return }
        // Asking for an image is asking to watch it being made, whatever the canvas had been
        // showing until now. Every other route into the queue leaves the canvas where it is.
        startFollowingRun()
        let seeds = min(max(count, 1), Self.batchLimit)
        let request = descriptor.capabilities.clamp(settings)
        let batch = UUID()
        let expanded = BatchExpansion.expand(request, count: seeds) { .random(in: .min ... .max) }
        for (index, settings) in expanded.enumerated() {
            queue.append(
                QueuedGeneration(
                    model: descriptor,
                    settings: settings,
                    batchID: batch,
                    batchIndex: index
                )
            )
        }
        if isDraining {
            logger.info("queued \(seeds) generation(s), \(self.queue.count) waiting")
        } else {
            drain()
        }
    }

    /// The images this run has produced so far, oldest first, so a strip of them reads in the
    /// order the seeds were queued and the empty places for what is still coming go on the end.
    public var currentBatch: [GeneratedImage] {
        guard let batch = activeBatchID else { return [] }
        return history.filter { $0.batchID == batch }.reversed()
    }

    /// How many of this run's seeds have yet to produce an image, the one being rendered
    /// included.
    public var pendingInCurrentBatch: Int {
        guard let batch = activeBatchID else { return 0 }
        return queue.count { $0.batchID == batch } + (running?.batchID == batch ? 1 : 0)
    }

    /// Which run "this run" means: the one being rendered, else the one waiting, else the one
    /// the newest image came from. Images restored from an earlier session carry no batch, so
    /// on a fresh launch there is no current run at all, which is the honest answer.
    private var activeBatchID: UUID? {
        running?.batchID ?? queue.first?.batchID ?? history.first?.batchID
    }
}
