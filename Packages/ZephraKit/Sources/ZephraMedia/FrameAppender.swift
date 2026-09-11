import AVFoundation
import CoreVideo
import Foundation

/// Feeds frames to a writer input as fast as it will take them.
///
/// `requestMediaDataWhenReady` calls back on its queue whenever the input can accept more;
/// each call appends until the input is full or the frames run out, and the last one marks
/// the input finished and resumes the waiting caller. That callback is the one way a
/// non-real-time input's readiness comes back: polled from outside, an input the writer has
/// paused for interleaving with a second track never reads ready again. Timestamps are
/// `Session.time(of:)`, frame indices over the rate as an exact rational, so a 24 fps clip
/// is 24 fps and not 23.98.
///
/// The frames come from `provider`, called with the index of the frame wanted next: a
/// `RGBAFrameSequence`'s bytes for the writer, a reader's decoded buffers for the stitcher.
final class FrameAppender: @unchecked Sendable {
    /// The frame at `index`, or nil when the clip is over.
    typealias Provider = (Int) throws -> CVPixelBuffer?

    private let count: Int
    private let session: MP4Writer.Session
    private let provider: Provider
    private let queue = DispatchQueue(label: "io.zephra.mp4-writer")
    // Both touched only on `queue`, which is what the unchecked Sendable conformance rests on.
    private var next = 0
    private var finished = false

    private var adaptor: AVAssetWriterInputPixelBufferAdaptor { session.adaptor }

    /// An appender over a sequence's RGBA bytes.
    convenience init(frames: RGBAFrameSequence, session: MP4Writer.Session) {
        self.init(count: frames.frameCount, session: session) { index in
            try Self.pixelBuffer(for: frames.frame(index), width: frames.width, height: frames.height, adaptor: session.adaptor)
        }
    }

    /// An appender over `count` frames handed back by `provider`.
    init(count: Int, session: MP4Writer.Session, provider: @escaping Provider) {
        self.count = count
        self.session = session
        self.provider = provider
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            adaptor.assetWriterInput.requestMediaDataWhenReady(on: queue) { [self] in
                guard !finished else { return }
                do {
                    while adaptor.assetWriterInput.isReadyForMoreMediaData, next < count {
                        try append(frame: next)
                        next += 1
                    }
                    if next == count {
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
        guard let buffer = try provider(index) else {
            throw MP4WriterError.encodingFailed("the clip ended before frame \(index)")
        }
        guard adaptor.append(buffer, withPresentationTime: session.time(of: index)) else {
            throw MP4WriterError.encodingFailed(
                adaptor.assetWriterInput.description + " refused frame \(index)")
        }
    }

    /// A BGRA pixel buffer from the adaptor's pool, filled from RGBA bytes with the channels
    /// swapped: hardware encoders take 32BGRA everywhere, and not every one takes 32RGBA.
    private static func pixelBuffer(
        for rgba: Data, width: Int, height: Int, adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) throws -> CVPixelBuffer {
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
        rgba.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            let src = source.bindMemory(to: UInt8.self)
            for row in 0..<height {
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
