import Foundation
import ZephraCore

/// Finding the picture a generation started from, given only the image it produced.
extension GenerationRecord {
    /// The folder imported source images are kept in, relative to the library root.
    public static let sourcesFolderName = "Sources"

    /// The reference this record names, resolved against an image that lives at `imageURL`.
    ///
    /// The record stores a bare file name, so the folder has to be worked out from where the
    /// image is. Two places are tried, in this order:
    ///
    /// 1. `Sources/` inside the image's own folder, which is where a generated image sitting
    ///    at the library root finds it.
    /// 2. `Sources/` beside the image's folder, which is where an image inside
    ///    `Recently Deleted/` — or any other sub-folder of the library — finds it.
    ///
    /// Neither is required to exist. When the file has been moved away or deleted, this
    /// answers nil and the restored settings simply carry no reference, rather than pointing
    /// at a path that would fail at generation time. `referenceFileName` and
    /// `referenceDigest` stay on the record either way, so an inspector can still say what the
    /// image was made from.
    public func reference(nextTo imageURL: URL) -> ReferenceImage? {
        guard let referenceFileName, let url = sourceURL(named: referenceFileName, nextTo: imageURL)
        else { return nil }
        return ReferenceImage(url: url, strength: referenceStrength ?? 0.6)
    }

    /// The first candidate folder that actually holds a file with this name.
    private func sourceURL(named name: String, nextTo imageURL: URL) -> URL? {
        let folder = imageURL.deletingLastPathComponent()
        let candidates = [
            folder.appending(path: Self.sourcesFolderName, directoryHint: .isDirectory),
            folder.deletingLastPathComponent()
                .appending(path: Self.sourcesFolderName, directoryHint: .isDirectory),
        ]
        return candidates
            .map { $0.appending(path: name, directoryHint: .notDirectory) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
