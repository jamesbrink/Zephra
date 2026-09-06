import Foundation

/// `index.json` at the root of a mirror, as `scripts/mirror-index.swift` writes it: every
/// variant the mirror holds, with its files, their sizes and their SHA-256 digests, and the
/// provenance stamp the packer wrote into it.
struct MirrorIndex: Decodable {
    /// One published variant.
    struct Variant: Decodable {
        /// What `.zephra-packed-source` in the variant says, repeated here so a client can tell
        /// before fetching twenty gigabytes whether they are the variant its catalog means.
        var source: [String]
        var files: [Entry]
    }

    /// One file of a variant.
    struct Entry: Decodable {
        var path: String
        var bytes: Int64
        var sha256: String
    }

    var models: [String: Variant]

    /// Reads the index, or throws `unreadableListing` when the bytes are not one.
    static func decode(_ data: Data) throws -> MirrorIndex {
        do {
            return try JSONDecoder().decode(MirrorIndex.self, from: data)
        } catch {
            throw ModelDownloadError.unreadableListing
        }
    }

    /// The files of `id`, when the index has it and says it was packed as `identity` describes;
    /// nil otherwise, which the caller reads as "not on this mirror".
    func files(of id: String, matching identity: [String]) -> [RepositoryFile]? {
        guard let variant = models[id], variant.source == identity else { return nil }
        return variant.files.map { RepositoryFile(path: $0.path, bytes: $0.bytes, sha256: $0.sha256) }
    }
}
