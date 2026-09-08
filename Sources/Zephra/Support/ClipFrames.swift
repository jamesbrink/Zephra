import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The last frame of a clip's MP4, as PNG bytes: what "Animate from Last Frame" hands the well.
///
/// `AVAssetImageGenerator` is asked for the frame a step before the asset's duration rather than
/// at the duration itself, which is past the last sample and would be refused; a step's
/// tolerance either side of that lets it land on the real last frame rather than one just short
/// of it. The bytes it copies out are re-encoded through `ReferenceImageEncoder`, the one place
/// a picture becomes what a reference is carried as, so a clip's last frame is capped and cast
/// exactly like every other door into the well.
///
/// Both entry points are `async` because AVFoundation's own are: loading a property off an asset
/// and generating an image are `load(.duration)` and `image(at:)`, and the synchronous pair they
/// replace is deprecated as far back as macOS 13. Nothing about the seam changes —
/// `GenerationStore.animate(origin:read:)` already takes an `async` closure and runs it off the
/// main actor, which is where these were being called from — and both stay `nonisolated`, so the
/// decode never lands on the main actor.
///
/// `lastFrame(ofMP4Data:)` is the same rule for a clip still in memory, with no file on disk yet
/// to read: the generator only reads from a URL, so the bytes go through a temporary file first.
enum ClipFrames {
    /// The clip's last frame, or nil when the asset has no readable frame there.
    nonisolated static func lastFrame(of url: URL) async -> Data? {
        // One step at LTX-2.5's frame rate, the only clip model this build ships. A `nonisolated`
        // function cannot read a stored static property under `SWIFT_DEFAULT_ACTOR_ISOLATION`, so
        // this is a local rather than a type-level constant.
        let frameStep = CMTime(value: 1, timescale: 24)
        let asset = AVURLAsset(url: url)
        // A file with no track to read a duration off throws rather than answering zero, which
        // is the same nil as a duration that is there and empty.
        guard let duration = try? await asset.load(.duration), duration.isValid, duration > .zero
        else { return nil }
        let target = max(duration - frameStep, .zero)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = frameStep
        generator.requestedTimeToleranceAfter = .zero
        guard let cgImage = try? await generator.image(at: target).image else { return nil }
        guard let rawPNG = pngData(from: cgImage) else { return nil }
        return ReferenceImageEncoder.pngData(from: rawPNG)
    }

    /// The same rule over a clip's MP4 bytes still held in memory, for a picture that has not
    /// reached the disk yet: `AVAssetImageGenerator` reads from a file, so the bytes are written
    /// to a uniquely named temporary file first and removed again once the frame is read,
    /// success or failure alike, rather than left for the poster's fallback to reach instead.
    nonisolated static func lastFrame(ofMP4Data data: Data) async -> Data? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zephra-clip-frame-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil else { return nil }
        return await lastFrame(of: url)
    }

    private nonisolated static func pngData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
