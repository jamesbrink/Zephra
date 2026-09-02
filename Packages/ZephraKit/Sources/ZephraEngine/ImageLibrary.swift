import Foundation
import ZephraCore

/// The folder finished images are written to, and the naming scheme that keeps them sortable in
/// the Finder. It is a value type with no cached state, so it can be handed to a background task.
public struct ImageLibrary: Sendable {
    /// The directory images are written into. Created on the first write, not before.
    public let root: URL

    /// Creates a library rooted at a directory that need not exist yet.
    public init(root: URL) {
        self.root = root
    }

    /// The default location: a Zephra folder inside the user's Pictures directory.
    public static func pictures() -> ImageLibrary {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Pictures")
        return ImageLibrary(root: pictures.appending(path: "Zephra", directoryHint: .isDirectory))
    }

    /// Writes the PNG bytes and returns where they landed, creating the folder if it is missing
    /// and stepping around a name that is somehow already taken.
    @discardableResult
    public func write(_ image: GeneratedImage) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = availableURL(named: fileName(for: image))
        try image.pngData.write(to: url, options: .atomic)
        return url
    }

    /// The most recently written images, newest first. An unreadable folder reads as empty,
    /// because a missing library is a normal state rather than a failure.
    public func recent(limit: Int) -> [URL] {
        guard limit > 0 else { return [] }
        let keys: [URLResourceKey] = [.creationDateKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "png" }
            .map { (url: $0, created: Self.creationDate(of: $0)) }
            .sorted { $0.created > $1.created }
            .prefix(limit)
            .map(\.url)
    }

    private func fileName(for image: GeneratedImage) -> String {
        "zephra-\(Self.stamp(image.createdAt))-s\(image.settings.seed).png"
    }

    private func availableURL(named name: String) -> URL {
        let first = root.appending(path: name)
        guard Self.exists(first) else { return first }
        let stem = first.deletingPathExtension().lastPathComponent
        for suffix in 2...99 {
            let candidate = root.appending(path: "\(stem)-\(suffix).png")
            if !Self.exists(candidate) { return candidate }
        }
        return first
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private static func creationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
