import Foundation

/// One picture a generation works from: the bytes, where they came from, and what shape they are.
///
/// Bytes and not a file URL, which is the contract `GenerationSettings.referenceImage` has always
/// carried: a settings value is what the user chose, and it has to keep meaning that after the
/// file is moved, after the app quits, and twenty minutes later when its queue entry finally
/// runs. The interface caps a picture at 1024 pixels an edge before it lands here, so one is a
/// megabyte or two, the same order as the images history already holds.
///
/// A model that reads several pictures reads them in this order, and
/// `ModelCapabilities.referenceImageCount` says how many it reads at all.
public struct ReferencePicture: Hashable, Sendable, Codable {
    /// The picture as PNG.
    ///
    /// Empty for a picture whose bytes were stripped to cross the link
    /// (`GenerationSettings.withoutPixels`), which keeps what the picture was without the
    /// megabytes exactly as `ClipContinuation.withoutPixels` keeps a clip's tail without its
    /// frames. Ask `hasPixels` rather than assuming; `GenerationSettings.referenceImage` answers
    /// nil for such a picture, and `ModelCapabilities.clamp` drops it.
    public var data: Data
    /// The library file name this picture came out of, when it came from the library, and nil
    /// when it came from a file chooser or a drop.
    ///
    /// A name and not a path, for the reason the record it is written into is inside the PNG: a
    /// library that survives being moved to another Mac cannot hold absolute paths. It is
    /// provenance for the person looking at the result — "this started from that picture" — and
    /// nothing reads it to find the file except an interface offering to show it.
    public var origin: String?
    /// What those bytes are, in pixels, as whoever encoded them measured it; nil when nobody
    /// did, and then a reader falls back to reading the PNG's own header.
    ///
    /// Stored rather than computed because `ZephraCore` cannot read a PNG — the walker lives in
    /// `ZephraEngine`, and moving it down here to serve one field would put the library's file
    /// format in the value layer — and because both reference encoders know the size at the
    /// moment they encode, so storing it saves a header read at every site that asks.
    public var size: ImageSize?

    /// Creates a picture from bytes, with whatever is known about where they came from.
    public init(data: Data, origin: String? = nil, size: ImageSize? = nil) {
        self.data = data
        self.origin = origin
        self.size = size
    }

    /// Whether the bytes are here, rather than having been stripped for the wire.
    public var hasPixels: Bool { !data.isEmpty }

    /// The same picture with its bytes dropped and everything it is *about* kept.
    public func withoutPixels() -> ReferencePicture {
        ReferencePicture(data: Data(), origin: origin, size: size)
    }
}
