import Foundation
import ZephraCore

/// A clip longer than one pass, made as a chain: each pass carries on from the last frames of
/// the one before, and the segments are joined once when the last lands.
///
/// Every pass is an ordinary queued generation on the same model and batch; what is
/// different is what happens when it finishes. A pass that is not the last is kept in memory
/// rather than published, its tail is read back, and the next pass is put at the head of the
/// queue with that tail as its continuation and the next seed. The last pass joins them all,
/// the source clip first when the chain began from one, and publishes one clip. Stop discards
/// the passes made so far, as it discards a single run; nothing reaches the canvas or the
/// library until the whole clip does.
extension GenerationStore {
    /// Registers a chain for `segments` when there is more than one, and answers the first
    /// pass's place in it; nil for a clip made in one pass.
    func startChain(segments: [Int], continuation: ClipContinuation?) -> ChainSegment? {
        guard segments.count > 1 else { return nil }
        let id = UUID()
        chains[id] = ChainProgress(segments: segments, source: continuation)
        return ChainSegment(chainID: id, index: 0, count: segments.count)
    }

    /// Takes the segment `job` made: keeps it and queues the next pass, answering nil, or,
    /// for the last pass, joins the chain and answers the whole clip with the clip it began
    /// from, when it did, for the record.
    ///
    /// The join needs the store's clip reader; a store without one never plans a chain, since
    /// `ChainPlan` answers one pass for a model that cannot continue, and `canQueue` is what
    /// the interface offers lengths by.
    func advanceChain(_ media: GeneratedMedia, job: QueuedGeneration, segment: ChainSegment)
        async throws -> (media: GeneratedMedia, source: ClipContinuation?)?
    {
        guard case .video(let clip) = media, let clips, var progress = chains[segment.chainID] else {
            throw BackendError.generationFailed("A chained clip lost its way between passes.")
        }
        progress.parts.append(
            ClipPart(mp4: clip.mp4, dropLeading: job.settings.continuation?.contextFrames ?? 0))
        if progress.poster == nil { progress.poster = clip.poster }
        chains[segment.chainID] = progress
        guard segment.isLast else {
            let context = job.model.capabilities.defaultContinuationFrames
            let tail = try await clips.tail(ofData: clip.mp4, frames: context)
            var next = job.settings
            next.frames = progress.segments[segment.index + 1]
            next.seed = next.seed &+ 1
            next.referenceImage = nil
            next.referenceOrigin = nil
            next.continuation = ClipContinuation(frames: tail, origin: nil, sourceFrameCount: clip.frameCount)
            queue.insert(
                QueuedGeneration(
                    model: job.model, settings: job.model.capabilities.clamp(next),
                    batchID: job.batchID, batchIndex: job.batchIndex,
                    chain: ChainSegment(chainID: segment.chainID, index: segment.index + 1, count: segment.count)),
                at: 0)
            return nil
        }
        chains[segment.chainID] = nil
        let context = job.model.capabilities.defaultContinuationFrames
        var parts = progress.parts
        var poster = progress.poster ?? clip.poster
        var frames = ChainPlan.joinedFrames(progress.segments, context: context)
        if let source = progress.source, let origin = source.origin {
            guard let found = library.sourceClip(named: origin) else {
                throw BackendError.generationFailed(
                    "The clip being extended, \(origin), is no longer in the library.")
            }
            parts.insert(ClipPart(mp4: try Data(contentsOf: found.mp4)), at: 0)
            poster = try Self.bare(poster: try Data(contentsOf: found.poster))
            frames += source.sourceFrameCount - source.contextFrames
        }
        let joined = GeneratedVideo(
            poster: poster, mp4: try await clips.stitch(parts), frameCount: frames,
            frameRate: clip.frameRate)
        return (.video(joined), progress.source)
    }

    /// The settings a chained clip is published with: the length the whole clip has, the
    /// seed the first pass ran on, and the clip it began from, if any.
    func chainedSettings(
        _ settings: GenerationSettings, segment: ChainSegment, frames: Int, source: ClipContinuation?
    ) -> GenerationSettings {
        var copy = settings
        copy.frames = frames
        copy.seed = settings.seed &- UInt64(segment.index)
        copy.continuation = source
        return copy
    }

    /// Forgets every chain in progress: what Stop and a failure do, since the passes made so
    /// far were never published.
    func dropChains() { chains.removeAll() }
}
