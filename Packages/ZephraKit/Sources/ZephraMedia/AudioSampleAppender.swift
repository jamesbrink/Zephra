import AVFoundation
import CoreMedia
import Foundation

/// Feeds an `AudioTrack` to a writer input as LPCM sample buffers, a second at a time.
///
/// The input encodes to AAC itself; what it takes is float32 interleaved LPCM with a format
/// description that says so, timestamped in sample frames over the rate. The chunks are
/// appended from `requestMediaDataWhenReady` on a queue of this appender's own, beside the
/// frames on theirs: that callback is how the writer paces two tracks against each other,
/// and an input polled from outside never reads ready again once the writer has paused it.
final class AudioSampleAppender: @unchecked Sendable {
    let track: AudioTrack
    let input: AVAssetWriterInput
    private let queue = DispatchQueue(label: "io.zephra.mp4-writer-audio")
    /// Touched only on `queue`, which is what the unchecked Sendable conformance rests on.
    private var next = 0
    /// Guards the two below, which `abandon` reaches from wherever the frames failed.
    private let lock = NSLock()
    private var waiting: CheckedContinuation<Void, any Error>?
    private var outcome: Result<Void, any Error>?

    init(track: AudioTrack, input: AVAssetWriterInput) {
        self.track = track
        self.input = input
    }

    /// One second of frames per buffer: few enough calls, small enough buffers.
    private var chunkFrames: Int { Int(track.sampleRate) }

    /// How many chunks the track appends.
    var chunkCount: Int { (track.frames + chunkFrames - 1) / chunkFrames }

    /// The presentation time of chunk `index`.
    func time(of index: Int) -> CMTime {
        CMTime(value: CMTimeValue(index * chunkFrames), timescale: CMTimeScale(track.sampleRate))
    }

    /// Appends every chunk as the input asks for them, and marks the input finished.
    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.lock()
            // Already given up, which is what frames that failed before this started look
            // like: the writer is being cancelled and must not be asked for anything more.
            if let settled = outcome {
                lock.unlock()
                continuation.resume(with: settled)
                return
            }
            waiting = continuation
            lock.unlock()
            input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !isSettled else { return }
                do {
                    while input.isReadyForMoreMediaData, next < chunkCount {
                        guard input.append(try buffer(chunk: next)) else {
                            throw MP4WriterError.encodingFailed("the writer refused audio chunk \(next)")
                        }
                        next += 1
                    }
                    if next == chunkCount { settle(.success(()), marking: true) }
                } catch {
                    settle(.failure(error), marking: true)
                }
            }
        }
    }

    /// Gives the track up so `run` returns rather than waiting on a writer that is about to be
    /// cancelled, and so a `run` that has not started yet never registers with one.
    ///
    /// What the session calls when the frames failed. It touches no AVFoundation: a cancelled
    /// writer raises rather than answers, and this is called a moment before the cancel.
    func abandon(_ error: any Error) { settle(.failure(error), marking: false) }

    /// Whether the track is done with, either way.
    private var isSettled: Bool { lock.withLock { outcome != nil } }

    /// Resumes `run` once; the one place the continuation is let go of. `marking` closes the
    /// input, which only the appender's own two endings do.
    private func settle(_ result: Result<Void, any Error>, marking: Bool) {
        lock.lock()
        guard outcome == nil else { return lock.unlock() }
        outcome = result
        let continuation = waiting
        waiting = nil
        lock.unlock()
        if marking { input.markAsFinished() }
        continuation?.resume(with: result)
    }

    /// The input's format: float32 interleaved LPCM at the track's rate and channel count.
    static func formatDescription(channels: Int, sampleRate: Double) throws -> CMAudioFormatDescription {
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0)
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0,
            magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard status == noErr, let format else {
            throw MP4WriterError.encodingFailed("no audio format description (\(status))")
        }
        return format
    }

    private func buffer(chunk index: Int) throws -> CMSampleBuffer {
        let start = index * chunkFrames
        let frames = min(chunkFrames, track.frames - start)
        let bytes = frames * track.channels * 4
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0,
            blockBufferOut: &block) == noErr, let block
        else { throw MP4WriterError.encodingFailed("no block buffer for audio chunk \(index)") }
        try track.samples.withUnsafeBytes { raw in
            let source = raw.baseAddress!.advanced(by: start * track.channels * 4)
            guard CMBlockBufferReplaceDataBytes(with: source, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) == noErr
            else { throw MP4WriterError.encodingFailed("audio chunk \(index) could not be copied") }
        }
        let format = try Self.formatDescription(channels: track.channels, sampleRate: track.sampleRate)
        var sample: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
            presentationTimeStamp: time(of: index), packetDescriptions: nil, sampleBufferOut: &sample)
        guard status == noErr, let sample else {
            throw MP4WriterError.encodingFailed("no sample buffer for audio chunk \(index) (\(status))")
        }
        return sample
    }
}
