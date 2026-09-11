import AVFoundation
import CoreVideo
import Foundation

extension MP4Writer {
    /// One H.264 track being written: the writer, its input and the pixel buffer adaptor,
    /// opened for a frame size and rate and closed by `finish`.
    ///
    /// Shared by `encode`, which feeds it a sequence through `FrameAppender`, and
    /// `MP4Stitcher`, which feeds it decoded frames one at a time. Video only: an audio track,
    /// when a model produces one, is added here before `startWriting` and appended in full
    /// before the first frame (see `MP4Writer`).
    final class Session {
        let width: Int
        let height: Int
        let frameRate: Double
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private let writer: AVAssetWriter

        init(to url: URL, width: Int, height: Int, frameRate: Double) throws {
            self.width = width
            self.height = height
            self.frameRate = frameRate
            do {
                writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            } catch {
                throw MP4WriterError.encodingFailed(error.localizedDescription)
            }
            // Width is the frame's columns and height its rows, which sounds obvious until
            // the decoder's `[frames, height, width, 3]` layout tempts a swap: the writer
            // refuses a size whose axes are crossed rather than making a sideways clip.
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                ])
            input.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                ])
            guard writer.canAdd(input) else {
                throw MP4WriterError.encodingFailed("The writer refused a \(width) x \(height) H.264 track.")
            }
            writer.add(input)
            guard writer.startWriting() else {
                throw MP4WriterError.encodingFailed(writer.error?.localizedDescription ?? "startWriting failed")
            }
            writer.startSession(atSourceTime: .zero)
        }

        /// The presentation time of frame `index`: its index over the rate as an exact
        /// rational. A timescale of a thousand times the rate keeps 23.976 as well as 24
        /// exact to the millihertz, rather than rounding the rate to a whole number.
        func time(of index: Int) -> CMTime {
            CMTime(value: CMTimeValue(index) * 1000, timescale: CMTimeScale((frameRate * 1000).rounded()))
        }

        /// Appends one frame as frame `index`, waiting while the encoder catches up.
        func append(_ buffer: CVPixelBuffer, at index: Int) async throws {
            while !adaptor.assetWriterInput.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(2))
            }
            guard adaptor.append(buffer, withPresentationTime: time(of: index)) else {
                throw MP4WriterError.encodingFailed(
                    writer.error?.localizedDescription ?? "the writer refused frame \(index)")
            }
        }

        /// Closes the track and the file.
        func finish() async throws {
            adaptor.assetWriterInput.markAsFinished()
            await writer.finishWriting()
            if writer.status != .completed {
                throw MP4WriterError.encodingFailed(writer.error?.localizedDescription ?? "finishWriting failed")
            }
        }

        /// Stops a session that will not be finished, so the writer releases the file.
        func abandon() {
            if writer.status == .writing { writer.cancelWriting() }
        }
    }
}
