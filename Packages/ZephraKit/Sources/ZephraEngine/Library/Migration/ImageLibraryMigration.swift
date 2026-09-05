import Foundation

/// Moves only Zephra's images and manifests, leaving unrelated files untouched.
public struct ImageLibraryMigration: Sendable {
    public let source: URL
    public let destination: URL

    public init(from source: URL, to destination: URL) {
        self.source = ImageDirectoryAccess.canonicalParent(of: source)
        self.destination = ImageDirectoryAccess.canonicalParent(of: destination)
    }

    func inventory() throws -> [ImageMigrationFile] {
        guard source.isFileURL, destination.isFileURL else {
            throw ImageDirectoryError("Choose local folders for images.")
        }
        let from = source.resolvingSymlinksInPath().path
        let to = destination.resolvingSymlinksInPath().path
        guard from != "/", to != "/", from != to,
              !from.hasPrefix(to + "/"), !to.hasPrefix(from + "/") else {
            throw ImageDirectoryError("Choose separate image folders; neither can be inside the other.")
        }
        let files = FileManager.default
        try ImageDirectoryAccess.requireMountedVolume(containing: source,
            mounted: files.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? [])
        try ImageDirectoryAccess.requireMountedVolume(containing: source.resolvingSymlinksInPath(),
            mounted: files.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? [])
        try ImageDirectoryAccess.requireDirectory(source)
        try ImageDirectoryAccess.requireDirectory(destination)
        guard files.fileExists(atPath: source.path) else { return [] }
        var found: [ImageMigrationFile] = []
        for directory in ["", "Sources", "Recently Deleted"] {
            let folder = directory.isEmpty ? source : source.appending(path: directory)
            try ImageDirectoryAccess.requireDirectory(folder)
            guard files.fileExists(atPath: folder.path) else { continue }
            for url in try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                let manifest = (directory.isEmpty && url.lastPathComponent == AlbumManifest.fileName)
                    || (directory == "Recently Deleted" && url.lastPathComponent == RecentlyDeletedManifest.fileName)
                guard manifest || url.pathExtension.lowercased() == "png" else { continue }
                // Check type before reading, so a FIFO or symlink is never opened.
                _ = try ImageMigrationFile.attributes(url)
                if !manifest {
                    let text: [String: String]
                    do { text = try PNGTextChunks.read(fromHeaderOf: url) }
                    catch is PNGTextChunks.Failure { continue }
                    guard GenerationRecord.decode(from: text) != nil || SourceRecord.decode(from: text) != nil
                    else { continue }
                }
                let path = directory.isEmpty ? url.lastPathComponent : directory + "/" + url.lastPathComponent
                let target = destination.appending(path: path)
                try ImageDirectoryAccess.requireDirectory(target.deletingLastPathComponent())
                guard (try? files.attributesOfItem(atPath: target.path)) == nil else {
                    throw ImageDirectoryError("An image or manifest already exists at \(target.path). Choose an empty folder to move this library.")
                }
                found.append(try ImageMigrationFile(url: url, path: path))
            }
        }
        if !found.isEmpty { try requireEmptyDestinationLibrary() }
        return found.sorted { $0.path < $1.path }
    }

    /// Manifests can refer to files or album IDs absent from the source. Even a
    /// noncolliding destination picture could inherit a name or an expired deletion date.
    private func requireEmptyDestinationLibrary() throws {
        let files = FileManager.default
        for directory in ["", "Sources", "Recently Deleted"] {
            let folder = directory.isEmpty ? destination : destination.appending(path: directory)
            try ImageDirectoryAccess.requireDirectory(folder)
            guard files.fileExists(atPath: folder.path) else { continue }
            let entries = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            let hasImagesOrMetadata = entries.contains { url in
                url.pathExtension.lowercased() == "png"
                    || (directory.isEmpty && url.lastPathComponent == AlbumManifest.fileName)
                    || (directory == "Recently Deleted" && url.lastPathComponent == RecentlyDeletedManifest.fileName)
            }
            guard !hasImagesOrMetadata else {
                throw ImageDirectoryError("The destination already contains images or library metadata. Choose an empty folder to move this library.")
            }
        }
    }
}
