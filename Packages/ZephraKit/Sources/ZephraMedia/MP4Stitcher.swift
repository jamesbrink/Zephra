import AVFoundation
import Foundation
import ZephraCore

/// Joins clips end to end into one MP4, and reads a clip's tail: the one `ClipEditing` the
/// composition root injects into the store.
///
/// The join decodes each part and encodes the frames again through one writer, the same H.264
/// settings `MP4Writer` uses, rather than splicing the streams: a splice keeps each part's own
/// encoder state and timing and needs the parts to have been made alike, and one re-encode of
/// a clip a few seconds long is cheap next to making it. Every part must share one frame size
/// and rate; the first part sets both and a part that differs is refused before a frame is
/// written. Frames are timestamped by their index over the rate, so the join is seamless.
/// Sound is carried when every part has a track of one channel count and rate, each part's
/// track trimmed by as many seconds as its dropped frames; a part without sound makes the
/// whole join silent.
public struct MP4Stitcher: ClipEditing {
    public init() {}

    public func tail(of url: URL, frames: Int) async throws -> [Data] {
        try await ClipTail.read(from: url, frames: frames)
    }

    public func tail(ofData mp4: Data, frames: Int) async throws -> [Data] {
        try await ClipTail.read(fromData: mp4, frames: frames)
    }

    public func stitch(_ parts: [ClipPart]) async throws -> Data {
        guard !parts.isEmpty else { throw MP4WriterError.emptyClip }
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "zephra-stitch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var urls: [URL] = []
        for (index, part) in parts.enumerated() {
            let url = folder.appending(path: "part-\(index).mp4")
            try part.mp4.write(to: url)
            urls.append(url)
        }
        let output = folder.appending(path: "stitched.mp4")
        try await Self.join(urls, dropping: parts.map(\.dropLeading), to: output)
        return try Data(contentsOf: output)
    }

    /// Reads each clip in turn and appends its frames past the dropped ones to one writer,
    /// with the parts' sound joined the same way when every part has some.
    private static func join(_ urls: [URL], dropping: [Int], to output: URL) async throws {
        var opened: [MP4FrameSource] = []
        for url in urls { opened.append(try await MP4FrameSource(url: url)) }
        let sources = opened
        guard let first = sources.first else { throw MP4WriterError.emptyClip }
        for source in sources {
            guard source.width == first.width, source.height == first.height,
                abs(source.frameRate - first.frameRate) < 0.01
            else { throw MP4WriterError.mismatchedParts }
        }
        let audio = try await ClipWork.run {
            try joinedAudio(sources, dropping: dropping, frameRate: first.frameRate)
        }
        let session = try MP4Writer.Session(
            to: output, width: first.width, height: first.height, frameRate: first.frameRate, audio: audio)
        // Frames are pulled from the parts one at a time as the writer asks for them, the
        // dropped ones at each part's head read and thrown away, until the parts run out. The
        // cursor is the count: a header's duration times its rate is a frame either side of
        // what a file decodes to, and a count one too high fails a good join.
        let cursor = PartCursor(sources: sources, dropping: dropping)
        try await session.run(frames: FrameAppender(count: nil, session: session) { _ in try cursor.next() })
    }

    /// A read position across the parts: the next frame past each part's dropped head.
    private final class PartCursor: @unchecked Sendable {
        private let sources: [MP4FrameSource]
        private let dropping: [Int]
        private var part = 0
        private var skipped = 0

        init(sources: [MP4FrameSource], dropping: [Int]) {
            self.sources = sources
            self.dropping = dropping
        }

        func next() throws -> CVPixelBuffer? {
            while part < sources.count {
                if let buffer = sources[part].next() {
                    if skipped < dropping[part] { skipped += 1; continue }
                    return buffer
                }
                if let failure = sources[part].failure {
                    throw MP4WriterError.encodingFailed(failure.localizedDescription)
                }
                part += 1
                skipped = 0
            }
            return nil
        }
    }

    /// The parts' sound end to end, each trimmed by its dropped frames' seconds, or nil when
    /// any part is silent or the tracks differ in shape.
    private static func joinedAudio(_ sources: [MP4FrameSource], dropping: [Int], frameRate: Double) throws -> AudioTrack? {
        guard let format = sources.first?.audioFormat else { return nil }
        var joined: AudioTrack?
        for (source, drop) in zip(sources, dropping) {
            guard let own = source.audioFormat, own.channels == format.channels, own.sampleRate == format.sampleRate,
                let samples = source.audioSamples(), !samples.isEmpty
            else { return nil }
            let track = try AudioTrack(samples: samples, channels: own.channels, sampleRate: own.sampleRate)
                .dropping(seconds: Double(drop) / frameRate)
            joined = joined.map { $0.appending(track) } ?? track
        }
        return joined
    }
}
