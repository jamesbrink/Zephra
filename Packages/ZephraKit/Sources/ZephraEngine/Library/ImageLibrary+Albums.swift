import Foundation

/// Reading and writing the album manifest. The images are the library; this file only says what
/// the albums are called and which ones are empty.
extension ImageLibrary {
    /// Where the manifest lives.
    public var albumManifestURL: URL {
        root.appending(path: AlbumManifest.fileName)
    }

    /// The manifest as it stands, or an empty one when there is no file, it cannot be read, or
    /// it was written by a build newer than this. A missing manifest is a normal state: it is
    /// only written once an album exists.
    public func albumManifest() -> AlbumManifest {
        guard let data = try? Data(contentsOf: albumManifestURL) else { return AlbumManifest() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(AlbumManifest.self, from: data),
              manifest.version <= AlbumManifest.currentVersion
        else { return AlbumManifest() }
        return manifest
    }

    /// The albums the library has: the manifest, plus any album an image names that the
    /// manifest has lost, in the order a sidebar should list them.
    public func albums(reconciledWith items: [LibraryItem]) -> [Album] {
        albumManifest().reconciled(with: items)
    }

    /// Writes the album list, creating the library folder if this is the first thing in it.
    public func writeAlbums(_ albums: [Album]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(AlbumManifest(albums: albums)).write(to: albumManifestURL, options: .atomic)
    }
}
