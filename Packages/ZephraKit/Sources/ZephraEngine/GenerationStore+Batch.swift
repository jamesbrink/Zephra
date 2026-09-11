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
        guard canQueue else {
            // Every press lands here, from the button and the menu bar alike; a press that
            // did nothing says so in `make logs`, with the gate that refused it.
            logger.info(
                "generate refused: prompt \(self.settings.isReadyToGenerate), engine \(self.state.acceptsGeneration || self.isDraining), adopting \(self.isAdoptingReference), work \(self.acceptsWork)")
            return
        }
        // Asking for an image is asking to watch it being made, whatever the canvas had been
        // showing until now. Every other route into the queue leaves the canvas where it is.
        startFollowingRun()
        // And asking for it on the chosen model is what a choice taken from a picture was
        // waiting for; the drain swaps to it as it takes the first entry.
        modelAwaitsGenerate = false
        capsuleHoldsPicture = false
        let seeds = min(max(count, 1), Self.batchLimit)
        // A clip longer than one pass is a chain of passes: the first is queued here with
        // the rest planned, and each pass queues the next as it lands. `clamp` keeps a single
        // pass's bounds, so the request the backend sees is never longer than it can run.
        let segments = ChainPlan.segments(frames: settings.frames, capabilities: descriptor.capabilities)
        var first = settings
        first.frames = segments[0]
        let request = descriptor.capabilities.clamp(first)
        let batch = UUID()
        let expanded = BatchExpansion.expand(request, count: seeds) { .random(in: .min ... .max) }
        for (index, settings) in expanded.enumerated() {
            queue.append(
                QueuedGeneration(
                    model: descriptor,
                    settings: settings,
                    batchID: batch,
                    batchIndex: index,
                    chain: startChain(segments: segments, continuation: request.continuation)
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
