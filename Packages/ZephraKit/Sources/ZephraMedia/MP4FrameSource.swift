import AVFoundation
import CoreVideo
import Foundation

/// A clip's frames read back out of its file one at a time, as 32BGRA pixel buffers, with the
/// track's size and frame rate.
///
/// `AVAssetReader` over the first video track, in presentation order. The reader hands buffers
/// back as they decode, so a clip of any length is walked in constant memory; the tail reader
/// keeps only the last few and the stitcher hands each straight to a writer. Frames are
/// counted rather than trusted from the header, since a frame count is what every caller
/// here is about.
final class MP4FrameSource {
    /// Pixels across.
    let width: Int
    /// Pixels down.
    let height: Int
    /// Frames per second, as the track says.
    let frameRate: Double

    /// The first audio track's channels and rate, or nil when the clip is silent.
    let audioFormat: (channels: Int, sampleRate: Double)?

    private let asset: AVURLAsset
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let audioTrack: AVAssetTrack?

    /// Opens the clip at `url`. Throws when there is no video track or the reader refuses it.
    ///
    /// `copyingSamples` makes every buffer the caller's own: a reader that hands back its
    /// decoder's pool may reuse a buffer once the next is asked for, which is fine for a
    /// caller that consumes each frame before asking again and not for one that keeps a few.
    init(url: URL, copyingSamples: Bool = false) async throws {
        let asset = AVURLAsset(url: url)
        self.asset = asset
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            throw MP4WriterError.notAClip
        }
        let size = try await track.load(.naturalSize)
        frameRate = Double(try await track.load(.nominalFrameRate))
        width = Int(size.width.rounded())
        height = Int(size.height.rounded())
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw MP4WriterError.encodingFailed(error.localizedDescription)
        }
        output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = copyingSamples
        guard reader.canAdd(output) else { throw MP4WriterError.notAClip }
        reader.add(output)
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
            let descriptions = try? await audioTrack.load(.formatDescriptions),
            let stream = descriptions.first?.audioStreamBasicDescription
        {
            audioFormat = (Int(stream.mChannelsPerFrame), stream.mSampleRate)
            self.audioTrack = audioTrack
        } else {
            audioFormat = nil
            audioTrack = nil
        }
        guard reader.startReading() else {
            throw MP4WriterError.encodingFailed(reader.error?.localizedDescription ?? "startReading failed")
        }
    }

    /// The next frame's pixels, or nil when the clip is over.
    func next() -> CVPixelBuffer? {
        guard let sample = output.copyNextSampleBuffer() else { return nil }
        return CMSampleBufferGetImageBuffer(sample)
    }

    /// The whole audio track as interleaved float samples, or nil for a silent clip.
    ///
    /// Through a reader of its own: one reader's outputs are paced against each other, and
    /// draining the sound before a frame has been read stalls on the frames.
    func audioSamples() -> [Float]? {
        guard let audioTrack, let format = audioFormat, let reader = try? AVAssetReader(asset: asset) else {
            return nil
        }
        let decoded = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channels,
            ])
        decoded.alwaysCopiesSampleData = true
        guard reader.canAdd(decoded) else { return nil }
        reader.add(decoded)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        var samples: [Float] = []
        while let sample = decoded.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: length)
            bytes.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            bytes.withUnsafeBytes { raw in samples.append(contentsOf: raw.bindMemory(to: Float.self)) }
        }
        return samples
    }

    /// Whether the reader stopped for a reason other than the end of the clip.
    var failure: (any Error)? {
        reader.status == .failed ? reader.error : nil
    }
}
