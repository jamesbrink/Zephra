import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZephraLinkHost

/// The app's thumbnail folder, seen as the seam a phone session asks through.
///
/// The folder already bakes off the main thread four at a time and keeps what it bakes, so a
/// phone scrolling a library pays for a decode once and every later launch — on either device —
/// reads the file. All this adds is the encode: the folder hands back a `CGImage` and the wire
/// wants JPEG.
///
/// JPEG rather than the folder's own HEIC, which is what it writes to disk: a phone decodes
/// either, but JPEG is what `BlobStart` names and what every other picture on the link is, and
/// one mime for one kind of payload is one fewer thing for both ends to agree about.
///
/// JPEG has no alpha channel, so a thumbnail of a transparent picture is laid over
/// `Checkerboard` here before it is encoded, deliberately, rather than flattened against
/// whatever Image I/O picks. The phone's grid cell then reads as transparent with no protocol
/// change and no second idea of what transparency looks like: the squares baked into the
/// picture are the squares both apps draw live.
struct CompanionThumbnails: ThumbnailSupply {
    /// How compressed a thumbnail crosses at. Higher than a preview frame's, because this is a
    /// picture somebody is looking at rather than a glimpse of a run in flight.
    static let quality = 0.8

    private let folder: ThumbnailFolder

    /// A supply over the app's one thumbnail folder.
    init(folder: ThumbnailFolder) {
        self.folder = folder
    }

    func thumbnail(for url: URL, pixels: Int) async -> Data? {
        guard let facts = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
            let modifiedAt = facts.contentModificationDate
        else { return nil }
        let key = ThumbnailKey(
            path: url.standardizedFileURL.path(percentEncoded: false),
            modifiedAt: modifiedAt,
            fileSize: Int64(facts.fileSize ?? 0),
            pixels: pixels)
        guard let image = await folder.image(for: key, of: url, pixels: pixels) else { return nil }
        return await Task.detached(priority: .utility) { Self.encode(image) }.value
    }

    /// One `CGImage` as JPEG bytes, off the main actor like every other decode in the app.
    ///
    /// An opaque thumbnail is encoded as it stands; one that carries alpha goes over the
    /// checkerboard first.
    private nonisolated static func encode(_ image: CGImage) -> Data? {
        guard let flattened = CheckerboardComposite.flattened(image) else { return nil }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            bytes, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, flattened, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return bytes as Data
    }
}
