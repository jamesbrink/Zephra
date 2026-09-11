import UIKit

/// The pictures this session has already fetched off the Mac, by file name.
///
/// A picture crosses the link once. Without this, walking to the library and back re-fetched
/// the whole PNG over what may be a relay on the far side of the world, for a picture already
/// on screen a second earlier. The name is enough of a key: a library file's name is its
/// identity everywhere in the protocol, and the Mac never rewrites a picture under one.
///
/// An actor, so the decode itself happens off the main actor — `UIImage(data:)` on a
/// twelve-megapixel PNG is tens of milliseconds, which is a dropped frame in the middle of a
/// scroll. Bounded, because a phone walking a library of thousands would otherwise hold every
/// one of them: the oldest arrival goes when the count is reached.
actor PictureCache {
    /// The one cache, since the point of it is that two surfaces share what they fetched.
    static let shared = PictureCache()

    /// How many decoded pictures to keep. A dozen full-size images is tens of megabytes, which
    /// is what a phone can spare; the thumbnails a grid draws are a different cache's business.
    private static let capacity = 12

    private var pictures: [String: UIImage] = [:]
    private var arrivals: [String] = []

    /// The picture already held for `name`, or nil.
    func picture(named name: String) -> UIImage? { pictures[name] }

    /// Decodes `data` as the picture for `name`, keeps it, and hands it back.
    func store(_ data: Data, for name: String) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        if pictures[name] == nil { arrivals.append(name) }
        pictures[name] = image
        while arrivals.count > Self.capacity {
            pictures.removeValue(forKey: arrivals.removeFirst())
        }
        return image
    }
}
