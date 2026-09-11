import AVFoundation
import CoreVideo
import Foundation

extension MP4Writer {
    /// One H.264 track being written: the writer, its input and the pixel buffer adaptor,
    /// opened for a frame size and rate and closed by `finish`.
    ///
    /// Shared by `encode`, which feeds it a sequence through `FrameAppender`, and
    /// `MP4Stitcher`, which feeds it decoded frames the same way. With an `audio` track a
    /// second input is added before `startWriting`, AAC at the track's rate and channels, fed
    /// by `AudioSampleAppender` on a queue of its own; `run` drives both appenders at once,
    /// which is the one way the writer's interleaving of two tracks makes progress.
    final class Session {
        let width: Int
        let height: Int
        let frameRate: Double
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        /// The audio appender, when the file has a track.
        let audio: AudioSampleAppender?
        private let writer: AVAssetWriter

        init(to url: URL, width: Int, height: Int, frameRate: Double, audio track: AudioTrack? = nil) throws {
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
            if let track {
                let audioInput = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVSampleRateKey: track.sampleRate,
                        AVNumberOfChannelsKey: track.channels,
                        AVEncoderBitRateKey: 192_000,
                    ],
                    sourceFormatHint: try AudioSampleAppender.formatDescription(
                        channels: track.channels, sampleRate: track.sampleRate))
                audioInput.expectsMediaDataInRealTime = false
                guard writer.canAdd(audioInput) else {
                    throw MP4WriterError.encodingFailed("The writer refused an AAC track at \(track.sampleRate) Hz.")
                }
                writer.add(audioInput)
                audio = AudioSampleAppender(track: track, input: audioInput)
            } else {
                audio = nil
            }
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

        /// Appends every frame `frames` hands back and the whole audio track, each input on
        /// its own queue as the writer asks, and closes the file. Throws whatever either
        /// appender threw, the file abandoned.
        func run(frames: FrameAppender) async throws {
            do {
                if let audio {
                    async let sound: Void = audio.run()
                    do {
                        try await frames.run()
                    } catch {
                        // The sound is still waiting on `requestMediaDataWhenReady`, which the
                        // writer stops calling the moment it is cancelled. Let it go first, or
                        // the implicit await on `sound` at the end of this scope waits for a
                        // callback that will never come.
                        audio.abandon(error)
                        throw error
                    }
                    try await sound
                } else {
                    try await frames.run()
                }
            } catch {
                abandon()
                throw error
            }
            try await finish()
        }

        /// Closes the tracks and the file; the appenders have marked their inputs finished.
        private func finish() async throws {
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
