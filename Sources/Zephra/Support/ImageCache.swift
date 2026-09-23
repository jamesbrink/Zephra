import AppKit
import Foundation
import ZephraCore

/// Decoded pixels for the images this session produced, keyed by image identity.
///
/// PNG bytes are decoded exactly once per image and kind, off the main actor, and thumbnails
/// are built by Image I/O at their final size rather than by scaling a full-resolution bitmap.
/// Views look pixels up here through `SessionImage`; they never decode inside `body`.
///
/// The shape is `ThumbnailCache`'s: `cached` is the cheap lookup a first frame may make,
/// `load` is the decode, coalesced so two views asking for the same picture at once share one
/// detached task, and the `DrawnPicture` is made on the main actor around the `CGImage` that
/// comes back, which is immutable and so may cross. What crosses with it is whether that
/// bitmap has alpha, read where the pixels are rather than in a view.
@MainActor
@Observable
final class ImageCache {
    /// What a view wants: the whole picture, or a thumbnail at the filmstrip's size.
    nonisolated enum Kind: Hashable, Sendable {
        case full
        case thumbnail
    }

    /// How the bytes become pixels. Injected so a test can count and slow the decodes.
    typealias Decoder = @Sendable (Data, Kind) -> CGImage?

    /// What a decode in flight is filed under, so a second request joins it.
    private enum Key: Hashable {
        case session(UUID, Kind)
        case reference(String)
    }

    private let decode: Decoder
    private let fullSize = NSCache<NSUUID, DrawnPicture>()
    private let thumbnails = NSCache<NSUUID, DrawnPicture>()
    private let references = NSCache<NSString, DrawnPicture>()
    @ObservationIgnored private var inFlight: [Key: Task<CGImage?, Never>] = [:]

    /// Creates an empty cache. One instance lives for the life of the window.
    init(decode: @escaping Decoder = ImageCache.decode) {
        self.decode = decode
        fullSize.countLimit = 8
        thumbnails.countLimit = 64
        references.countLimit = 4
    }

    /// The pixels already in memory, or nil. Cheap enough to read in `body`, which is what
    /// lets a view draw a picture it has seen before on its first frame rather than after a
    /// flash of nothing.
    func cached(_ image: GeneratedImage, _ kind: Kind) -> DrawnPicture? {
        store(for: kind).object(forKey: image.id as NSUUID)
    }

    /// The pixels for one image, from memory or freshly decoded off the main actor.
    ///
    /// The decode is detached and shared, so a caller that is cancelled — a canvas that moved
    /// on — neither stops it nor wastes it: the pixels land in memory for the next view to ask,
    /// and nil comes back so a stale picture is never handed to a view that has moved on.
    func load(_ image: GeneratedImage, _ kind: Kind) async -> DrawnPicture? {
        if let hit = cached(image, kind) { return hit }
        let key = Key.session(image.id, kind)
        guard let decoded = await coalesced(key, image.pngData, kind) else { return nil }
        // Two callers that shared the decode share the object too: whichever resumes first
        // makes it, and the other finds it.
        let made = cached(image, kind) ?? DrawnPicture(decoded)
        store(for: kind).setObject(made, forKey: image.id as NSUUID)
        return Task.isCancelled ? nil : made
    }

    /// A small bitmap for the reference well, keyed by a digest of the bytes: a reference has
    /// no session identity of its own, and the same picture dropped twice is the same key.
    /// A digest and not `hashValue`, which reads only a prefix of a `Data` and would show the
    /// wrong picture for two files that agree on their first bytes. The digest is a pass over
    /// the whole PNG, so it is taken off the main actor with the decode.
    func referenceThumbnail(_ png: Data) async -> DrawnPicture? {
        let hex = await Task.detached(priority: .userInitiated) { Self.digest(of: png) }.value
        let cacheKey = hex as NSString
        if let hit = references.object(forKey: cacheKey) { return hit }
        guard let decoded = await coalesced(.reference(hex), png, .thumbnail) else { return nil }
        let made = references.object(forKey: cacheKey) ?? DrawnPicture(decoded)
        references.setObject(made, forKey: cacheKey)
        return made
    }

    /// One decode per key at a time: a request that finds one running awaits it instead.
    private func coalesced(_ key: Key, _ data: Data, _ kind: Kind) async -> CGImage? {
        let task = inFlight[key] ?? Task.detached(priority: .userInitiated) { [decode] in
            decode(data, kind)
        }
        inFlight[key] = task
        let decoded = await task.value
        inFlight[key] = nil
        return decoded
    }

    private func store(for kind: Kind) -> NSCache<NSUUID, DrawnPicture> {
        switch kind {
        case .full: fullSize
        case .thumbnail: thumbnails
        }
    }
}
