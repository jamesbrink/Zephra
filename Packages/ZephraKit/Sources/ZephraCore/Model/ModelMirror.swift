import Foundation

/// Where copies of the variants Zephra packs are published, so a Mac can fetch one instead of
/// downloading the release it is packed from and packing it itself.
///
/// The mirror is one directory of static files behind HTTPS, laid out the way `make mirror`
/// writes it: `index.json` at the root naming every variant it holds, its files, their sizes
/// and their SHA-256 digests, and under `<descriptor id>/` exactly what `locations.built` holds
/// on a Mac, provenance stamp included. Nothing about it is a repository: there is no revision
/// to pin, because a variant's identity is the stamp the index repeats, and there is no
/// listing to page, because the index is the listing.
///
/// Fetching from it is a preference of the catalog, not a promise: a variant the index does
/// not name, or names as packed from something other than what the catalog says, is simply not
/// on the mirror, and the model is built here the way it always was.
public struct ModelMirror: Hashable, Sendable {
    /// The directory the index and the variants are under, with no trailing slash needed.
    public let base: URL

    /// A mirror rooted at `base`.
    public init(base: URL) {
        self.base = base
    }

    /// Where the index that names every variant lives.
    public var index: URL { base.appending(path: "index.json") }

    /// Where one file of the variant `id` is served from.
    public func file(_ path: String, of id: String) -> URL {
        base.appending(path: id).appending(path: path)
    }
}
