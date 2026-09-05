import Foundation
import ZephraSnapshot

extension ImageLibraryMigration {
    /// Returns warnings for originals retained after the complete destination was published.
    public func run(progress: @Sendable (String) -> Void = { _ in }) throws -> [String] {
        try run(progress: progress, copy: FileManager.default.copyItem,
                publish: FileManager.default.moveItem, removeSource: FileManager.default.removeItem)
    }

    func run(
        progress: @Sendable (String) -> Void = { _ in },
        copy: (URL, URL) throws -> Void = FileManager.default.copyItem,
        publish: (URL, URL) throws -> Void = FileManager.default.moveItem,
        removeSource: (URL) throws -> Void = FileManager.default.removeItem,
        availableBytes: Int64? = nil
    ) throws -> [String] {
        progress("Checking image files…")
        let entries = try inventory()
        try ImageDirectoryAccess.prepare(destination)
        let files = FileManager.default
        let needed = entries.reduce(Int64(0)) { $0 + $1.bytes }
        // `volumeAvailableCapacityForImportantUsage`, which counts purgeable space, rather than
        // `.systemFreeSize`, which does not: the same reading every transfer reserves against.
        guard let free = try availableBytes ?? TransferCapacity.read(destination).available,
              free >= needed + 64 * 1024 * 1024 else {
            throw ImageDirectoryError("Not enough free space in \(destination.path) to copy and verify the images.")
        }
        let stage = destination.appending(path: ".zephra-image-migration-\(UUID().uuidString)")
        try files.createDirectory(at: stage, withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: stage) }
        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            progress("Copying image file \(index + 1) of \(entries.count)…")
            let staged = stage.appending(path: entry.path)
            try files.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
            try copy(entry.url, staged)
            try entry.verify(at: staged)
        }
        try Task.checkCancellation()
        var published: [ImageMigrationFile] = []
        do {
            for entry in entries {
                let target = destination.appending(path: entry.path)
                try ImageDirectoryAccess.requireDirectory(destination)
                try ImageDirectoryAccess.requireDirectory(target.deletingLastPathComponent())
                try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try publish(stage.appending(path: entry.path), target)
                published.append(entry)
            }
        } catch {
            var retained: [String] = []
            for entry in published.reversed() {
                let target = destination.appending(path: entry.path)
                do {
                    try entry.verify(at: target)
                    try files.removeItem(at: target)
                } catch { retained.append(target.path) }
            }
            let detail = retained.isEmpty ? "" : " Copies retained at: " + retained.joined(separator: ", ") + "."
            throw ImageDirectoryError("Could not finish publishing the images. All originals remain in \(source.path).\(detail) \(error.localizedDescription)")
        }
        // Publication is complete: adopt the destination even when cleanup cannot finish.
        var warnings: [String] = []
        for entry in entries {
            do {
                try ImageDirectoryAccess.requireDirectory(source)
                try ImageDirectoryAccess.requireDirectory(entry.url.deletingLastPathComponent())
                try entry.verify(at: destination.appending(path: entry.path))
                try removeSource(entry.url)
            } catch {
                warnings.append("Images were copied, but \(entry.url.path) was kept: \(error.localizedDescription)")
            }
        }
        return warnings
    }
}
