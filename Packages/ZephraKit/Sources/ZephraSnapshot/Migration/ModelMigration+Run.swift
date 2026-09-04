import Foundation

extension ModelMigration {
    /// Copies and verifies all models before publishing any. Returns source-cleanup warnings.
    public func run(progress: @Sendable (String) -> Void = { _ in }) throws -> [String] {
        try run(progress: progress, publish: FileManager.default.moveItem,
                removeSource: FileManager.default.removeItem)
    }

    /// File operations are injectable to exercise publication and cleanup failures separately.
    func run(
        progress: @Sendable (String) -> Void,
        publish: (URL, URL) throws -> Void,
        removeSource: (URL) throws -> Void,
        availableBytes: Int64? = nil
    ) throws -> [String] {
        progress("Checking model files…")
        let paths = try directories()
        let trees = try paths.map { try ModelFileTree(source.appending(path: $0)) }
        try ModelDirectoryAccess.prepare(destination)
        let capacity = try FileManager.default.attributesOfFileSystem(forPath: destination.path)
        let needed = trees.reduce(Int64(0)) { $0 + $1.bytes }
        guard let free = availableBytes ?? (capacity[.systemFreeSize] as? NSNumber)?.int64Value,
              free >= needed + 64 * 1024 * 1024 else {
            throw ModelDirectoryError("Not enough free space in \(destination.path) to copy and verify the models.")
        }
        let stage = destination.appending(path: ".zephra-migration-\(UUID().uuidString)")
        let files = FileManager.default
        try files.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: stage) }
        for (index, tree) in trees.enumerated() {
            progress("Copying model \(index + 1) of \(trees.count)…")
            let staged = stage.appending(path: paths[index])
            try tree.copy(to: staged)
            progress("Verifying model \(index + 1) of \(trees.count)…")
            try tree.verify(at: staged)
        }
        try Task.checkCancellation()
        var published: [String] = []
        do {
            for path in paths {
                let target = destination.appending(path: path)
                try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                // moveItem refuses an existing target. Never replace another copy.
                try publish(stage.appending(path: path), target)
                published.append(path)
            }
        } catch {
            throw ModelDirectoryError("Could not finish publishing the models. All originals remain in \(source.path). \(published.count) verified copies remain in \(destination.path). \(error.localizedDescription)")
        }
        // From this point the destination is complete. Cleanup failures must not roll back
        // the setting to a source from which some models have already been removed.
        var warnings: [String] = []
        for (index, tree) in trees.enumerated() {
            progress("Finishing model \(index + 1) of \(trees.count)…")
            do {
                try tree.verify(at: destination.appending(path: paths[index]))
                try removeSource(tree.root)
            } catch {
                warnings.append("Models were copied, but \(tree.root.path) was kept: \(error.localizedDescription)")
            }
        }
        return warnings
    }
}
