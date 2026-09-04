import Foundation

/// Validates the chosen destination without silently using another disk.
public enum ModelDirectoryAccess {
    public static func prepare(_ directory: URL) throws {
        let files = FileManager.default
        let path = directory.standardizedFileURL.path
        guard directory.isFileURL, path.hasPrefix("/") else {
            throw ModelDirectoryError("Choose a local folder for models.")
        }
        try requireMountedVolume(containing: directory,
                                 mounted: files.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? [])
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe = directory.appending(path: ".zephra-write-check-\(UUID().uuidString)")
        do {
            try Data().write(to: probe, options: .withoutOverwriting)
            try files.removeItem(at: probe)
        } catch {
            throw ModelDirectoryError("Cannot write to \(path). \(error.localizedDescription)")
        }
    }

    /// Path identity ignores the directory hint carried by mounted-volume URLs.
    static func requireMountedVolume(containing directory: URL, mounted: [URL]) throws {
        let parts = directory.standardizedFileURL.pathComponents
        if parts.count > 2, parts[1] == "Volumes" {
            let volume = URL(filePath: "/Volumes").appending(path: parts[2])
            guard mounted.contains(where: { $0.standardizedFileURL.path == volume.standardizedFileURL.path }) else {
                throw ModelDirectoryError("Connect the disk containing \(directory.path) and try again.")
            }
        }
    }
}
