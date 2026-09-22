import Foundation
import ZephraCore

/// What a continuation's segment becomes: the source clip with the segment joined on the end.
///
/// The join runs inside the generation, after the backend has handed the segment back and
/// before the result is published, so everything downstream — the canvas, history, the wall,
/// the save — sees one finished clip and nothing about it changes. The segment begins with
/// the frames the model was handed to hold, which are the source's own last frames re-drawn;
/// they are dropped so the join lands on the first frame the model made.
extension GenerationStore {
    /// `media` as the clip `job` carries on, joined onto its source; `media` itself when the
    /// job carried no continuation or made no clip.
    ///
    /// The source is looked up by its library name in the images folder, then in Recently
    /// Deleted, since a clip deleted while its continuation waited in the queue is still there
    /// for thirty days. A source that is nowhere, or a join that fails, is a failed generation:
    /// the segment alone is not what was asked for.
    func stitched(_ media: GeneratedMedia, job: QueuedGeneration) async throws -> GeneratedMedia {
        guard let continuation = job.settings.continuation, let origin = continuation.origin,
            let clips, case .video(let segment) = media
        else { return media }
        guard let source = library.sourceClip(named: origin) else {
            throw BackendError.generationFailed(
                "The clip being extended, \(origin), is no longer in the library.")
        }
        let poster = try Self.bare(poster: try Data(contentsOf: source.poster))
        let joined = try await clips.stitch([
            ClipPart(mp4: try Data(contentsOf: source.mp4)),
            ClipPart(mp4: segment.mp4, dropLeading: continuation.contextFrames),
        ])
        return .video(
            GeneratedVideo(
                poster: poster, mp4: joined,
                frameCount: continuation.sourceFrameCount + segment.frameCount - continuation.contextFrames,
                frameRate: segment.frameRate, hasAudio: segment.hasAudio))
    }

    /// A source's poster without the source's own record, reference, annotation and captions:
    /// the new clip gets a record of its own when it is written, and a poster already carrying
    /// one would keep it.
    static func bare(poster: Data) throws -> Data {
        try PNGTextChunks.removing(
            Set(
                [GenerationRecord.keyword] + GenerationRecord.allReferenceKeywords
                    + [LibraryAnnotation.keyword, "Software", "Description"]),
            from: poster)
    }

    /// The settings a continued clip is published and recorded with: the tail's pictures
    /// dropped, so history never holds them, and no reference picture, since the frame in
    /// the well was the source's own last frame and not a picture the clip was edited from.
    static func published(_ settings: GenerationSettings) -> GenerationSettings {
        guard let continuation = settings.continuation else { return settings }
        var copy = settings
        copy.continuation = continuation.withoutPixels()
        copy.referenceImages = []
        return copy
    }
}
