import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The Image I/O half: reading a baked thumbnail back, making one, and throwing old ones away.
///
/// All of it is `nonisolated` and static. None of it touches the actor's state, and every call
/// is made from inside a detached task, which is the point: a decode must never happen on the
/// main actor, and the type system should be the thing that says so.
extension ThumbnailFolder {
    /// A thumbnail already on disk, or nil when there is none there.
    nonisolated static func read(_ file: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { return nil }
        return image
    }

    /// Makes a thumbnail from the full-size picture and writes it beside the others.
    ///
    /// `CreateThumbnailFromImageAlways` rather than the embedded preview a camera would have
    /// left: a PNG Zephra wrote has no embedded preview, and a picture imported from elsewhere
    /// may have one at the wrong size or of the wrong thing. `ShouldCacheImmediately` decodes
    /// here, in this task, rather than lazily on whichever thread first draws the pixels — which
    /// would be the main one.
    nonisolated static func bake(_ url: URL, pixels: Int, to file: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: pixels,
              ] as CFDictionary)
        else { return nil }
        // A thumbnail that cannot be written is still a thumbnail. The next launch bakes it
        // again, which costs a decode; refusing to show the picture would cost the picture.
        write(thumbnail, to: file)
        return thumbnail
    }

    /// Writes one thumbnail as HEIC, which is a third of the bytes of a JPEG of the same
    /// quality and has no generation loss worth worrying about at this size.
    private nonisolated static func write(_ image: CGImage, to file: URL) {
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            file as CFURL, UTType.heic.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.8,
        ] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    /// Deletes every thumbnail last asked for before `cutoff`, and any shard folder left empty.
    ///
    /// The access date is what "asked for" means, and the file system is the thing that keeps
    /// it. Where it is not kept the modification date stands in, which is when the thumbnail was
    /// baked — so a thumbnail in constant use may still be swept after thirty days. That costs
    /// one bake, which is the right way round for a cache to be wrong.
    nonisolated static func discardEntries(under directory: URL, lastUsedBefore cutoff: Date) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentAccessDateKey, .contentModificationDateKey]
        guard let shards = try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for shard in shards {
            let entries = (try? manager.contentsOfDirectory(
                at: shard, includingPropertiesForKeys: keys
            )) ?? []
            for entry in entries {
                let values = try? entry.resourceValues(forKeys: Set(keys))
                let used = values?.contentAccessDate ?? values?.contentModificationDate ?? .now
                guard used < cutoff else { continue }
                try? manager.removeItem(at: entry)
            }
            if entries.isEmpty || (try? manager.contentsOfDirectory(
                atPath: shard.path(percentEncoded: false)
            ))?.isEmpty == true {
                try? manager.removeItem(at: shard)
            }
        }
    }
}
