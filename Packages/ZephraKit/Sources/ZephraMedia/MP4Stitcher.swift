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

    /// Reads each clip in turn and appends its frames past the dropped ones to one writer.
    private static func join(_ urls: [URL], dropping: [Int], to output: URL) async throws {
        var writer: MP4Writer.Session?
        var written = 0
        defer { writer?.abandon() }
        for (url, drop) in zip(urls, dropping) {
            let source = try await MP4FrameSource(url: url)
            let session = try writer ?? MP4Writer.Session(
                to: output, width: source.width, height: source.height, frameRate: source.frameRate)
            writer = session
            guard source.width == session.width, source.height == session.height,
                abs(source.frameRate - session.frameRate) < 0.01
            else { throw MP4WriterError.mismatchedParts }
            var index = 0
            while let buffer = source.next() {
                defer { index += 1 }
                guard index >= drop else { continue }
                try await session.append(buffer, at: written)
                written += 1
            }
            if let failure = source.failure {
                throw MP4WriterError.encodingFailed(failure.localizedDescription)
            }
        }
        guard written > 0, let writer else { throw MP4WriterError.emptyClip }
        try await writer.finish()
    }
}
