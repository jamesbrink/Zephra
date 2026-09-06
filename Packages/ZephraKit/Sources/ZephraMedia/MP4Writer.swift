import AVFoundation
import CoreVideo
import Foundation

/// Encodes a clip's frames into an H.264 MP4 through `AVAssetWriter`, hardware encoder first.
///
/// The writer works on a file, so the frames go through a temporary in the caller's temp
/// directory and come back as bytes; the file is removed either way. Video only for now: when a
/// model produces audio, its track is appended *before* the frames, because appending a second
/// track after a long video track deadlocks the writer's interleaving (the two-track stall the
/// Swift LTX port hit and fixed the same way).
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
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw MP4WriterError.encodingFailed(error.localizedDescription)
        }
        // Width is the frame's columns and height its rows, which sounds obvious until the
        // decoder's `[frames, height, width, 3]` layout tempts a swap: the writer refuses a
        // size whose axes are crossed rather than making a sideways clip.
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: frames.width,
                AVVideoHeightKey: frames.height,
            ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: frames.width,
                kCVPixelBufferHeightKey as String: frames.height,
            ])
        guard writer.canAdd(input) else {
            throw MP4WriterError.encodingFailed("The writer refused a \(frames.width) x \(frames.height) H.264 track.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw MP4WriterError.encodingFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)
        try await FrameAppender(frames: frames, frameRate: frameRate, adaptor: adaptor).run()
        await writer.finishWriting()
        if writer.status != .completed {
            throw MP4WriterError.encodingFailed(writer.error?.localizedDescription ?? "finishWriting failed")
        }
    }
}
