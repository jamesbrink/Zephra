import AVFoundation
import CoreVideo
import Foundation

/// Encodes a clip's frames into an H.264 MP4 through `AVAssetWriter`, hardware encoder first.
///
/// The writer works on a file, so the frames go through a temporary in the caller's temp
/// directory and come back as bytes; the file is removed either way. Video only for now: when a
/// model produces audio, its track is appended *before* the frames, because appending a second
/// track after a long video track deadlocks the writer's interleaving (the two-track stall the
/// Swift LTX port hit and fixed the same way). The track itself is `MP4Writer.Session`, which
/// `MP4Stitcher` shares to join clips.
public enum MP4Writer {
    /// Encodes `frames` at `frameRate` frames per second and returns the MP4's bytes.
    public static func encode(_ frames: RGBAFrameSequence, frameRate: Double) async throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "zephra-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await write(frames, frameRate: frameRate, to: url)
        return try Data(contentsOf: url)
    }

    private static func write(_ frames: RGBAFrameSequence, frameRate: Double, to url: URL)
        async throws
    {
        let session = try Session(
            to: url, width: frames.width, height: frames.height, frameRate: frameRate)
        do {
            try await FrameAppender(frames: frames, session: session).run()
        } catch {
            session.abandon()
            throw error
        }
        try await session.finish()
    }
}
