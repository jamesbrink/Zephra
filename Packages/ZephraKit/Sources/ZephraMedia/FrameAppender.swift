import AVFoundation
import CoreVideo
import Foundation

/// Feeds a sequence's frames to a writer input as fast as it will take them.
///
/// `requestMediaDataWhenReady` calls back on its queue whenever the input can accept more;
/// each call appends until the input is full or the frames run out, and the last one marks
/// the input finished and resumes the waiting caller. Timestamps are frame indices over the
/// frame rate as an exact rational, so a 24 fps clip is 24 fps and not 23.98.
final class FrameAppender: @unchecked Sendable {
    private let frames: RGBAFrameSequence
    private let frameRate: Double
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let queue = DispatchQueue(label: "io.zephra.mp4-writer")
    // Both touched only on `queue`, which is what the unchecked Sendable conformance rests on.
    private var next = 0
    private var finished = false

    init(frames: RGBAFrameSequence, frameRate: Double, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
        self.frames = frames
        self.frameRate = frameRate
        self.adaptor = adaptor
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            adaptor.assetWriterInput.requestMediaDataWhenReady(on: queue) { [self] in
                guard !finished else { return }
                do {
                    while adaptor.assetWriterInput.isReadyForMoreMediaData, next < frames.frameCount {
                        try append(frame: next)
                        next += 1
                    }
                    if next == frames.frameCount {
                        finished = true
                        adaptor.assetWriterInput.markAsFinished()
                        continuation.resume()
                    }
                } catch {
                    finished = true
                    adaptor.assetWriterInput.markAsFinished()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func append(frame index: Int) throws {
        let buffer = try pixelBuffer(for: frames.frame(index))
        // A timescale of a thousand times the rate keeps 23.976 as well as 24 exact to the
        // millihertz, rather than rounding the rate to a whole number.
        let time = CMTime(value: CMTimeValue(index) * 1000, timescale: CMTimeScale((frameRate * 1000).rounded()))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw MP4WriterError.encodingFailed(
                adaptor.assetWriterInput.description + " refused frame \(index)")
        }
    }

    /// A BGRA pixel buffer from the adaptor's pool, filled from RGBA bytes with the channels
    /// swapped: hardware encoders take 32BGRA everywhere, and not every one takes 32RGBA.
    private func pixelBuffer(for rgba: Data) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
            let buffer
        else {
            throw MP4WriterError.encodingFailed("no pixel buffer from the writer's pool")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw MP4WriterError.encodingFailed("pixel buffer has no base address")
        }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let width = frames.width
        rgba.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            let src = source.bindMemory(to: UInt8.self)
            for row in 0..<frames.height {
                let out = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
                let inRow = row * width * 4
                for x in 0..<width {
                    let i = inRow + x * 4
                    out[x * 4] = src[i + 2]
                    out[x * 4 + 1] = src[i + 1]
                    out[x * 4 + 2] = src[i]
                    out[x * 4 + 3] = src[i + 3]
                }
            }
        }
        return buffer
    }
}
