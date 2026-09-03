import Foundation

/// A throwaway directory tree, removed when the test's value goes out of scope.
///
/// Every suite that touches the file system builds its fixture through this, so a failing test
/// leaves nothing behind and two tests never share a path. It lives in its own product because
/// both the snapshot suites and every backend package's suites need it; a copy per package is
/// the thing this exists to avoid.
public final class Scratch {
    /// The root every path is created under.
    public let root: URL

    public init(_ label: String = "Zephra") {
        root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// Creates `path` under the root, as a directory or as an empty file.
    @discardableResult
    public func make(_ path: String, isDirectory: Bool = false) throws -> URL {
        let url = root.appending(path: path)
        let files = FileManager.default
        try files.createDirectory(
            at: isDirectory ? url : url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !isDirectory { try Data().write(to: url) }
        return url
    }

    /// Creates `path` under the root holding `text`.
    @discardableResult
    public func write(_ text: String, to path: String) throws -> URL {
        let url = try make(path)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// Creates `path` under the root as a symbolic link to `destination`, which is taken
    /// relative to the link, the way a hub snapshot points at the blob store.
    @discardableResult
    public func link(_ path: String, to destination: String) throws -> URL {
        let url = root.appending(path: path)
        let files = FileManager.default
        try files.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.createSymbolicLink(
            atPath: url.path(percentEncoded: false), withDestinationPath: destination)
        return url
    }

    /// The URL of `path` under the root, whether or not anything is there.
    public func url(_ path: String) -> URL {
        root.appending(path: path)
    }

    /// Whether `path` under the root is a file whose bytes are there to read, rather than a
    /// dangling link or nothing at all.
    public func hasFile(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path(percentEncoded: false))
    }
}
