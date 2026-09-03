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
    ///
    /// What goes on disk is the image with its `GenerationRecord` inside it, so the file is the
    /// only thing the history needs at the next launch.
    @discardableResult
    public func write(_ image: GeneratedImage) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = availableURL(named: fileName(for: image))
        try Self.annotated(image).write(to: url, options: .atomic)
        return url
    }

    /// The bytes to write: the image with its record embedded, or the plain pixels when that
    /// could not be done. A picture on disk without its provenance beats no picture at all.
    private static func annotated(_ image: GeneratedImage) -> Data {
        (try? GenerationRecord.embedded(in: image)) ?? image.pngData
    }

    private func fileName(for image: GeneratedImage) -> String {
        "zephra-\(Self.stamp(image.createdAt))-s\(image.settings.seed).png"
    }

    /// A name nothing in the library root is using yet.
    func availableURL(named name: String) -> URL {
        availableURL(named: name, in: root)
    }

    /// A name nothing in `directory` is using yet: the plain one, then `-2` through `-99`, then
    /// a UUID. The last step exists so a full run of suffixes can never make a write clobber an
    /// image. Moving an image to Recently Deleted and back needs the same rule as writing one.
    func availableURL(named name: String, in directory: URL) -> URL {
        let first = directory.appending(path: name)
        guard Self.exists(first) else { return first }
        let stem = first.deletingPathExtension().lastPathComponent
        for suffix in 2...99 {
            let candidate = directory.appending(path: "\(stem)-\(suffix).png")
            if !Self.exists(candidate) { return candidate }
        }
        return directory.appending(path: "\(stem)-\(UUID().uuidString.lowercased()).png")
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
