import Foundation
import ZephraCore

/// Reading the library back, and taking an image out of it. The two halves of a history that
/// outlives the session it was made in.
extension ImageLibrary {
    /// The newest images on disk that carry a Zephra record, newest first, at most `limit` of
    /// them.
    ///
    /// A file without a record — a foreign PNG dropped into the folder, or one saved by a build
    /// older than this one — is skipped rather than shown with invented settings. Files are read
    /// newest-first and only until `limit` records have been found, so a folder of thousands
    /// costs a couple of dozen reads.
    ///
    /// The order is the records' own timestamps, not the file system's, so images copied in from
    /// another Mac sit where they belong rather than where they landed.
    public func restore(limit: Int) -> [GeneratedImage] {
        guard limit > 0 else { return [] }
        var found: [GeneratedImage] = []
        for url in recent(limit: .max) {
            guard let data = try? Data(contentsOf: url),
                  let record = GenerationRecord.read(from: data)
            else { continue }
            found.append(
                record.image(
                    pngData: data, fileURL: url,
                    referenceImage: GenerationRecord.reference(in: data)))
            if found.count == limit { break }
        }
        return found.enumerated()
            .sorted { first, second in
                first.element.createdAt == second.element.createdAt
                    ? first.offset < second.offset
                    : first.element.createdAt > second.element.createdAt
            }
            .map(\.element)
    }

    /// Moves a file to the Trash, so deleting an image is always something the user can undo
    /// from the Finder.
    ///
    /// Not every location has a Trash to move to — a volume without one, and some temporary
    /// directories — and `trashItem` fails there. Leaving the file behind after the interface
    /// has already dropped the image would be worse than the delete being final, so in that
    /// case it is removed outright.
    public func discard(_ url: URL) throws {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            try FileManager.default.removeItem(at: url)
        }
    }
}
