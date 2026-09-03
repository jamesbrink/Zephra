import Foundation

/// The list of albums, kept in one hidden file in the library root.
///
/// A cache with one job the pictures cannot do: remember an album that has nothing in it yet,
/// and remember the current name of one whose images have not been rewritten. Delete the file
/// and the library rebuilds everything but those two things from the images themselves, which
/// is the property that makes a folder of PNGs a whole library.
public struct AlbumManifest: Hashable, Sendable, Codable {
    /// The file it is kept in, hidden so the Finder does not show it beside the pictures.
    public static let fileName = ".zephra-albums.json"
    /// The shape written today; a manifest claiming a higher version is left alone and read
    /// as nothing, so a newer build's albums are never rewritten by an older one.
    public static let currentVersion = 1

    /// Which shape this manifest is in.
    public var version: Int
    /// Every album that exists, whether or not anything is in it.
    public var albums: [Album]

    /// A manifest listing `albums`.
    public init(albums: [Album] = []) {
        self.version = Self.currentVersion
        self.albums = albums
    }

    /// The albums the library has, given what the manifest says and what the images say.
    ///
    /// The manifest wins on the name: it is where a rename lands, and an image still carrying
    /// the old one is simply behind. An album id an image names that the manifest has never
    /// heard of is recreated from the image, which is how a lost manifest comes back.
    public func reconciled(with items: [LibraryItem], now: Date = Date()) -> [Album] {
        var found = albums
        var known = Set(albums.map(\.id))
        for item in items {
            for membership in item.annotation.albums where !known.contains(membership.id) {
                known.insert(membership.id)
                found.append(
                    Album(id: membership.id, name: membership.name, createdAt: item.createdAt))
            }
        }
        return found.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedSame
                ? $0.createdAt < $1.createdAt
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
