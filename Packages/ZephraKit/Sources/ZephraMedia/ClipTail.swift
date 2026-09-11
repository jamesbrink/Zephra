import CoreVideo
import Foundation

/// The last frames of a clip, read back out of its MP4 as PNGs: what a continuation is handed,
/// and what "Animate from Last Frame" puts in the well when asked for one.
///
/// The whole clip is decoded in order, because H.264 frames depend on the ones before them
/// and a seek to the end lands on a keyframe rather than the last frame; only the last `frames`
/// buffers are kept, so the cost is one decode and a few frames of memory. The rate and size
/// are the track's own, so a clip at any frame rate reads back as itself.
public enum ClipTail {
    /// The last `frames` frames of the clip at `url`, oldest first; fewer when it is shorter.
    public static func read(from url: URL, frames: Int) async throws -> [Data] {
        guard frames > 0 else { return [] }
        let source = try await MP4FrameSource(url: url, copyingSamples: true)
        return try await ClipWork.run { try lastFrames(frames, of: source) }
    }

    /// The last `frames` frames the source hands back, as PNGs. Every call in here blocks
    /// until its bytes have decoded, which is why the reads above run it on `ClipWork`.
    private static func lastFrames(_ frames: Int, of source: MP4FrameSource) throws -> [Data] {
        var kept: [CVPixelBuffer] = []
        kept.reserveCapacity(frames)
        while let buffer = source.next() {
            if kept.count == frames { kept.removeFirst() }
            kept.append(buffer)
        }
        if let failure = source.failure {
            throw MP4WriterError.encodingFailed(failure.localizedDescription)
        }
        return try kept.map { buffer in
            guard let png = PixelBufferPNG.encode(buffer) else {
                throw MP4WriterError.encodingFailed("a decoded frame could not be encoded as PNG")
            }
            return png
        }
    }

    /// The same over a clip's bytes still in memory: the reader works on a file, so the bytes
    /// go through a temporary that is removed either way.
    public static func read(fromData mp4: Data, frames: Int) async throws -> [Data] {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "zephra-tail-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try mp4.write(to: url)
        return try await read(from: url, frames: frames)
    }
}
