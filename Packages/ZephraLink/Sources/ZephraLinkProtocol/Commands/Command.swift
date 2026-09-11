import Foundation

/// Everything the phone may ask the Mac to do.
///
/// One enum, so the Mac has one place that decides what a command means and one place that
/// refuses the ones `GenerationStore.acceptsWork` will not take. Nothing here changes a
/// preference or a folder: settings stay on the Mac, where the person can see what they are
/// agreeing to.
public enum Command: Hashable, Sendable {
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
    /// Send back this picture's file, or a clip's MP4.
    case fetchFile(name: String)
    /// Send back a window onto the library.
    case libraryPage(offset: Int, limit: Int)
}
