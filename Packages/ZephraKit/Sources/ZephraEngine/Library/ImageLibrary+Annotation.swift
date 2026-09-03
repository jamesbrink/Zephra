import Foundation

/// Reading and writing what the user said about an image, without touching what produced it.
extension ImageLibrary {
    /// The prefix of the temporary file an annotation is written through. Hidden, so a scan
    /// steps over it, and recognisable, so a scan can sweep one up after a crash.
    public static let annotationTemporaryPrefix = ".zephra-annotate-"

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

    /// Writes `annotation` into the file at `url` and returns what the file now looks like to a
    /// scan: its modification date and its size.
    ///
    /// The bytes are rewritten through a temporary file in the same directory and swapped in
    /// with `replaceItemAt`, which keeps the creation date, the permissions, and the Finder's
    /// own metadata. That matters more than it sounds: the library sorts by when an image was
    /// made, and a plain overwrite would move every image you favourited to the top.
    ///
    /// Both facts come back because both are what a rescan compares. Recording them means the
    /// next scan recognises a file this app wrote rather than reading its header again.
    @discardableResult
    public func annotate(
        _ url: URL,
        with annotation: LibraryAnnotation
    ) throws -> (modifiedAt: Date, size: Int64) {
        let data = try Data(contentsOf: url)
        let rewritten = try PNGTextChunks.replacing([try annotation.entry()], in: data)
        let files = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appending(path: "\(Self.annotationTemporaryPrefix)\(UUID().uuidString).png")
        try rewritten.write(to: temporary, options: .atomic)
        let result: URL
        do {
            result = try files.replaceItemAt(url, withItemAt: temporary) ?? url
        } catch {
            try? files.removeItem(at: temporary)
            throw error
        }
        // Read through a URL built from the path rather than the one `replaceItemAt` hands back:
        // that one carries resource values cached during the swap, a fraction of a millisecond
        // behind what a scan will read, and the two have to compare equal.
        let fresh = URL(filePath: result.path(percentEncoded: false))
        let values = try? fresh.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (
            modifiedAt: values?.contentModificationDate ?? Date(),
            size: Int64(values?.fileSize ?? rewritten.count)
        )
    }

    /// Removes annotation temporaries left behind by a crash between the write and the swap.
    ///
    /// Only ones older than a minute, so a write that is happening right now is never pulled out
    /// from under itself: this is for the file nobody is coming back for, not for tidiness.
    public func sweepAnnotationTemporaries(olderThan age: TimeInterval = 60, now: Date = Date()) {
        let files = FileManager.default
        for root in scanRoots {
            let directory = root.url
            let contents = (try? files.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsSubdirectoryDescendants]
            )) ?? []
            for url in contents
            where url.lastPathComponent.hasPrefix(Self.annotationTemporaryPrefix) {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                guard now.timeIntervalSince(modified) > age else { continue }
                try? files.removeItem(at: url)
            }
        }
    }
}
