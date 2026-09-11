import Foundation

/// Reading frames back out of a clip and joining clips end to end, as the engine needs them
/// for continuing a clip.
///
/// A protocol here rather than a call into `ZephraMedia`, because `ZephraEngine` takes
/// `ZephraCore` and `ZephraSnapshot` and nothing else: the one implementation lives beside
/// `MP4Writer` and the composition root injects it, the way the upscaler arrives as a
/// factory. A store built without one, in a tool or a preview, cannot extend a clip and
/// says so through `GenerationStore.canExtend`.
public protocol ClipEditing: Sendable {
    /// The last `frames` frames of the clip at `url`, oldest first, each as PNG bytes; fewer
    /// when the clip is shorter. Throws when the file is not a readable clip.
    func tail(of url: URL, frames: Int) async throws -> [Data]

    /// The same over a clip's bytes still in memory.
    func tail(ofData mp4: Data, frames: Int) async throws -> [Data]

    /// `parts` joined in order into one clip, each part's leading frames dropped as it says.
    /// Every part must share one frame size and rate. Returns the MP4's bytes.
    func stitch(_ parts: [ClipPart]) async throws -> Data
}
