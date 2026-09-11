import Foundation

/// Where a phone's thumbnails come from: JPEG bytes for one picture at one size.
///
/// A seam rather than a call into the app's own thumbnail folder, because that folder is an
/// actor in the app target and this package sits under it. The app conforms one small type over
/// `ThumbnailFolder`, which already bakes off the main thread and coalesces requests; a test
/// conforms a stub that hands back a couple of bytes.
///
/// JPEG rather than the baked HEIC: a phone decodes either, and the one the Mac already has on
/// disk is at whatever size the Mac's own grid asked for. Nil for a picture that cannot be read
/// at all, which the session answers as `notFound`.
public protocol ThumbnailSupply: Sendable {
    /// A thumbnail of the picture at `url`, `pixels` on its long edge, as JPEG bytes.
    func thumbnail(for url: URL, pixels: Int) async -> Data?
}
