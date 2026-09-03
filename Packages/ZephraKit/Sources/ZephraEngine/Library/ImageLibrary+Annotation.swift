import Foundation

/// Reading and writing what the user said about an image, without touching what produced it.
extension ImageLibrary {
    /// The annotation on the file at `url`, or `.none` for a file that carries none, is not a
    /// PNG, or cannot be read at all.
    ///
    /// Only the header is read: annotations sit ahead of the image data, so this costs a
    /// kilobyte or two whatever the picture weighs. An unreadable file answering "nothing was
    /// said" rather than throwing is deliberate — the caller is drawing a grid, and a file that
    /// has just been moved is not an error worth a dialog.
    public func annotation(at url: URL) -> LibraryAnnotation {
        guard let text = try? PNGTextChunks.read(fromHeaderOf: url) else { return .none }
        return LibraryAnnotation.decode(from: text)
    }

    /// Writes `annotation` into the file at `url` and returns its new modification date.
    ///
    /// The bytes are rewritten through a temporary file in the same directory and swapped in
    /// with `replaceItemAt`, which keeps the creation date, the permissions, and the Finder's
    /// own metadata. That matters more than it sounds: the library sorts by when an image was
    /// made, and a plain overwrite would move every image you favourited to the top.
    ///
    /// The date comes back so the caller can record it as the file's own: a scan compares
    /// modification dates to decide what to re-read, and an annotation it wrote itself should
    /// not look like a change somebody made in the Finder.
    @discardableResult
    public func annotate(_ url: URL, with annotation: LibraryAnnotation) throws -> Date {
        let data = try Data(contentsOf: url)
        let rewritten = try PNGTextChunks.replacing([try annotation.entry()], in: data)
        let files = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".zephra-annotate-\(UUID().uuidString).png")
        try rewritten.write(to: temporary, options: .atomic)
        let result: URL
        do {
            result = try files.replaceItemAt(url, withItemAt: temporary) ?? url
        } catch {
            try? files.removeItem(at: temporary)
            throw error
        }
        // Asked of the file system rather than of the URL: the URL `replaceItemAt` hands back
        // carries resource values cached during the swap, which are a fraction of a millisecond
        // behind the ones a scan will read.
        let attributes = try? files.attributesOfItem(atPath: result.path(percentEncoded: false))
        return attributes?[.modificationDate] as? Date ?? Date()
    }
}
