import Foundation

/// Validates a selected library folder before any preference changes.
public enum ImageDirectoryAccess {
    /// The check every write makes: the volume is mounted, and the folder exists. The full
    /// `prepare` — the symlink walk, the write probe — belongs to choosing the folder, which
    /// `changeImageDirectory` does once; a check that expensive on every save was not worth
    /// what it caught. The mounted check stays because an unmounted disk is exactly the case a
    /// write must refuse rather than recreate the folder on the mount point.
    public static func prepareForWrite(_ directory: URL) throws {
        let files = FileManager.default
        guard directory.isFileURL else { throw ImageDirectoryError("Choose a local folder for images.") }
        let mounted = files.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
        try requireMountedVolume(containing: directory, mounted: mounted)
        try requireMountedVolume(containing: directory.resolvingSymlinksInPath(), mounted: mounted)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func prepare(_ directory: URL) throws {
        let files = FileManager.default
        guard directory.isFileURL else { throw ImageDirectoryError("Choose a local folder for images.") }
        let directory = canonicalParent(of: directory)
        try requireMountedVolume(containing: directory,
            mounted: files.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? [])
        try requireMountedVolume(containing: directory.resolvingSymlinksInPath(),
            mounted: files.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? [])
        try requireDirectory(directory)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe = directory.appending(path: ".zephra-write-check-\(UUID().uuidString)")
        do {
            try Data().write(to: probe, options: .withoutOverwriting)
            try files.removeItem(at: probe)
        } catch {
            throw ImageDirectoryError("Cannot write to \(directory.path). \(error.localizedDescription)")
        }
    }

    static func requireMountedVolume(containing directory: URL, mounted: [URL]) throws {
        let parts = directory.standardizedFileURL.pathComponents
        if parts.count > 2, parts[1] == "Volumes" {
            guard mounted.contains(where: { $0.standardizedFileURL.path == "/Volumes/" + parts[2] }) else {
                throw ImageDirectoryError("Connect the disk containing \(directory.path) and try again.")
            }
        }
    }

    static func canonicalParent(of directory: URL) -> URL {
        let normalized = directory.standardizedFileURL
        return normalized.deletingLastPathComponent().resolvingSymlinksInPath()
            .appending(path: normalized.lastPathComponent, directoryHint: .isDirectory)
    }

    // Foundation deliberately canonicalizes /private/var back to /var. These protected
    // macOS aliases are safe only while they point to their expected system directory.
    private static func isSystemAlias(_ url: URL) -> Bool {
        guard ["/var", "/tmp", "/etc"].contains(url.path),
              let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
        else { return false }
        return target == "/private" + url.path || target == "private" + url.path
    }

    static func requireDirectory(_ directory: URL) throws {
        var component = directory
        while component.path != "/" {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: component.path),
               attributes[.type] as? FileAttributeType != .typeDirectory,
               !isSystemAlias(component) {
                throw ImageDirectoryError("This folder is a symbolic link or is not a directory: \(component.path).")
            }
            component.deleteLastPathComponent()
        }
    }
}
