import Foundation

/// Everything the phone may ask the Mac to do.
///
/// One enum, so the Mac has one place that decides what a command means and one place that
/// refuses the ones `GenerationStore.acceptsWork` will not take. Nothing here changes a
/// preference or a folder: settings stay on the Mac, where the person can see what they are
/// agreeing to.
/// Requests may retry after a lost reply, except `upscale`, which has no deduplication key
/// and must be sent once. `enqueue` is answered from the session's existing work, keyed by
/// `GenerationRequest.requestID`; state-setting commands and reads are safe to repeat.
public enum Command: Hashable, Sendable {
    case multiHost(MultiHostCommand)
    /// Send the whole state again: the phone stepped over a hole in the stream and no longer
    /// trusts what it is holding. Answered `.ok`, then a fresh `snapshot`.
    case resync
    /// Queue a press of Generate.
    case enqueue(GenerationRequest)
    /// Stop whatever is running.
    case cancel
    /// Take one entry out of the queue.
    case removeFromQueue(UUID)
    /// Empty the queue.
    case clearQueue
    /// Choose another model, by descriptor identifier.
    case switchModel(String)
    /// Choose this model if it is not the chosen one, and read its weights in now.
    ///
    /// The phone's Try Again after a GPU fault, and its Load control. Not `switchModel` of the
    /// model already chosen, which is a no-op the Mac answers `.ok` to — a phone drawing
    /// success over nothing having happened.
    case loadModel(String)
    /// Give the weights and their disk lease back, leaving the chosen model chosen.
    case unloadModel
    /// Mark these pictures as favorites, or unmark them.
    case setFavourite(names: [String], on: Bool)
    /// Replace the tags on these pictures.
    case setTags(names: [String], tags: [String])
    /// Move these pictures to Recently Deleted.
    case delete([String])
    /// Make this picture larger.
    case upscale(name: String, factor: Int)
    /// Make a clip from this picture.
    case animate(name: String)
    /// Send back a thumbnail of this picture, `pixels` on its long edge.
    case fetchThumbnail(name: String, pixels: Int)
    /// Send back this picture's file, or a clip's MP4, from `fromChunk` onwards.
    ///
    /// A whole file is hundreds of chunks over the relay and thousands for a clip, so a transfer
    /// a hole stopped at chunk 630 used to cost all 630 again. `fromChunk` is what the asker
    /// already holds, and it is still safe to repeat: the Mac reads the same file and sends the
    /// same tail, and a Mac too old to know the key sends the whole thing from zero, which the
    /// asker's reassembly starts fresh on.
    case fetchFile(name: String, fromChunk: UInt32 = 0)
    /// Send back a window onto the library.
    case libraryPage(offset: Int, limit: Int)
}
