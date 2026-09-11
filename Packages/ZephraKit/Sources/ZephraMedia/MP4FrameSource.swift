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

    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    /// Opens the clip at `url`. Throws when there is no video track or the reader refuses it.
    ///
    /// `copyingSamples` makes every buffer the caller's own: a reader that hands back its
    /// decoder's pool may reuse a buffer once the next is asked for, which is fine for a
    /// caller that consumes each frame before asking again and not for one that keeps a few.
    init(url: URL, copyingSamples: Bool = false) async throws {
        let asset = AVURLAsset(url: url)
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
        guard reader.startReading() else {
            throw MP4WriterError.encodingFailed(reader.error?.localizedDescription ?? "startReading failed")
        }
    }

    /// The next frame's pixels, or nil when the clip is over.
    func next() -> CVPixelBuffer? {
        guard let sample = output.copyNextSampleBuffer() else { return nil }
        return CMSampleBufferGetImageBuffer(sample)
    }

    /// Whether the reader stopped for a reason other than the end of the clip.
    var failure: (any Error)? {
        reader.status == .failed ? reader.error : nil
    }
}
