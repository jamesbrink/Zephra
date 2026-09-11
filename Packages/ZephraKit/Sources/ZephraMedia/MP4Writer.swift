import AVFoundation
import CoreVideo
import Foundation

/// Encodes a clip's frames into an H.264 MP4 through `AVAssetWriter`, hardware encoder first.
///
/// The writer works on a file, so the frames go through a temporary in the caller's temp
/// directory and come back as bytes; the file is removed either way. With an `audio` track the
/// file gets an AAC track beside the H.264 one, each fed from its own
/// `requestMediaDataWhenReady` callback at once: the writer paces two tracks against each
/// other by pausing whichever is ahead, and it lifts the pause only through that callback, so
/// an input appended to by polling — all of one track first, or the two in turn — stalls for
/// good part way through (the two-track stall the Swift LTX port hit). The track itself is
/// `MP4Writer.Session`, which `MP4Stitcher` shares to join clips.
public enum MP4Writer {
    /// Encodes `frames` at `frameRate` frames per second, with `audio` beside them when there
    /// is a track, and returns the MP4's bytes.
    public static func encode(
        _ frames: RGBAFrameSequence, frameRate: Double, audio: AudioTrack? = nil
    ) async throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "zephra-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await write(frames, frameRate: frameRate, audio: audio, to: url)
        return try Data(contentsOf: url)
    }

    private static func write(
        _ frames: RGBAFrameSequence, frameRate: Double, audio: AudioTrack?, to url: URL
    ) async throws {
        let session = try Session(
            to: url, width: frames.width, height: frames.height, frameRate: frameRate, audio: audio)
        try await session.run(frames: FrameAppender(frames: frames, session: session))
    }
}
