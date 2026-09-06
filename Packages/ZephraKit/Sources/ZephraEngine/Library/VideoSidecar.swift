import Foundation

/// The one rule about where a clip's MP4 lives: beside its poster PNG, under the same stem.
///
/// The library indexes the poster — an ordinary Zephra PNG carrying the record — and the clip
/// is a companion file the record never names, because a name is what changes when Put Back
/// steps around a collision. Every operation that moves, copies or deletes a PNG asks here
/// whether a companion is beside it and takes it along; a PNG without one is a picture.
public enum VideoSidecar {
    /// The container extension every clip is written with.
    public static let pathExtension = "mp4"

    /// Where `png`'s clip would be.
    public static func url(beside png: URL) -> URL {
        png.deletingPathExtension().appendingPathExtension(pathExtension)
    }

    /// The clip beside `png`, or nil when the picture is not a clip's poster or its clip is
    /// not there. The poster's own record is what says it is a clip: a same-stem MP4 beside a
    /// picture that never had one is somebody else's file, and is left alone.
    public static func existing(beside png: URL) -> URL? {
        guard let text = try? PNGTextChunks.read(fromHeaderOf: png),
            GenerationRecord.decode(from: text)?.isVideo == true
        else { return nil }
        let candidate = url(beside: png)
        return FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false))
            ? candidate : nil
    }

    /// Whether `url` is a clip file rather than a picture.
    public static func isSidecar(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == pathExtension
    }
}
