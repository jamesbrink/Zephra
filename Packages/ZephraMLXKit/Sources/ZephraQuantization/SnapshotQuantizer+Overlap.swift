import Foundation

/// The one thing the quantizer checks before it reads: that writing the build cannot destroy
/// what it is built from.
extension SnapshotQuantizer {
    /// Refuses a destination that is the source, inside it, or around it, links followed.
    ///
    /// The packer empties each component directory it writes to before reading the component,
    /// and `SnapshotBuild` replaces the destination whole, so either overlap deletes the release
    /// the build was reading, with `--out` spelled one directory wrong. Links are followed on
    /// both sides, and a destination that does not exist yet is resolved through its deepest
    /// existing ancestor: Foundation hands a missing path back unresolved, so a link to the
    /// release with a new name under it would pass a comparison of the spelled paths.
    public static func requireDisjoint(source: URL, destination: URL) throws {
        let sourcePath = resolved(source).pathComponents
        let destinationPath = resolved(destination).pathComponents
        if sourcePath.starts(with: destinationPath) || destinationPath.starts(with: sourcePath) {
            throw QuantizationError.destinationOverlapsSource(
                source: source, destination: destination)
        }
    }

    /// `url` with every link followed, including one in an ancestor of a path that does not
    /// exist yet.
    static func resolved(_ url: URL) -> URL {
        let files = FileManager.default
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while !files.fileExists(atPath: existing.path(percentEncoded: false)),
            existing.pathComponents.count > 1
        {
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath().standardizedFileURL
        for component in missing {
            resolved.append(path: component)
        }
        return resolved
    }
}
