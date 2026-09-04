import Foundation

/// Whether a path from the hub's listing may be written where it names. The listing is the
/// hub's word, not ours, and the download's folder is the one place Zephra writes.
extension ModelDownloader {
    /// Whether `path` stays inside `destination`: no empty or `..` component, no leading
    /// slash, and the target under the folder once both have their links followed. A
    /// component that is already a link out of the folder would otherwise pass on its name
    /// and be written through.
    static func isContained(_ path: String, target: URL, in destination: URL) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != ".." && $0 != "." })
        else { return false }
        guard let root = Self.resolved(destination), let target = Self.resolved(target) else {
            return false
        }
        return target.hasPrefix(root + "/")
    }

    /// The path with every link followed: the part that exists yet, through `realpath`, with
    /// the rest kept as named. Foundation's own resolution leaves a path whose leaf is not
    /// there yet alone, links in the middle and all, which here is exactly the case that
    /// matters. Nil when the part that exists cannot be resolved, such as a link to nowhere,
    /// which is refused rather than guessed at.
    private static func resolved(_ url: URL) -> String? {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        var info = stat()
        while lstat(Self.trimmed(existing), &info) != 0, existing.pathComponents.count > 1 {
            tail.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        guard let real = realpath(Self.trimmed(existing), nil) else { return nil }
        defer { free(real) }
        return ([String(cString: real)] + tail).joined(separator: "/")
    }

    private static func trimmed(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
