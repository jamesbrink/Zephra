import Foundation

extension GenerationStore {
    public var isChangingImageDirectory: Bool { imageDirectoryProgress != nil }

    public var canChangeImageDirectory: Bool {
        !isChangingImageDirectory && !isChangingModelDirectory && !isShuttingDown
            && !deletionInProgress && !isDraining
            && !isUpscaling && queue.isEmpty && running == nil && state != .cancelling
    }

    /// Changes every library reader and writer together, after their outstanding work settles.
    /// The caller persists this choice only after the operation succeeds.
    public func changeImageDirectory(
        to destination: URL, moving: Bool, index: LibraryIndex
    ) async throws -> [String] {
        guard canChangeImageDirectory, !index.isChangingDirectory else {
            throw ImageDirectoryError("Finish generation and queued work before changing the images folder.")
        }
        guard library.root.standardizedFileURL == index.library.root.standardizedFileURL else {
            throw ImageDirectoryError("The image library and its index must use the same folder.")
        }
        let target = destination.standardizedFileURL
        guard target != library.root.standardizedFileURL else { return [] }
        let settlement = StorageSettlement()
        storageSettlement = settlement
        imageDirectoryProgress = "Preparing images folder…"
        defer {
            imageDirectoryProgress = nil
            Task { await settlement.finish() }
        }
        openTask?.cancel()
        openTask = nil
        await index.pauseForDirectoryChange()
        await saveTask?.value
        await libraryTask?.value
        let source = library.root
        let updates = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let progress = Task {
            for await message in updates.stream { imageDirectoryProgress = message }
        }
        let operation = Task.detached(priority: .utility) {
            defer { updates.continuation.finish() }
            if moving {
                return try ImageLibraryMigration(from: source, to: target).run { message in
                    updates.continuation.yield(message)
                }
            }
            try ImageDirectoryAccess.prepare(target)
            return [String]()
        }
        let outcome = await operation.result
        await progress.value
        do {
            let warnings = try outcome.get()
            library = ImageLibrary(root: target)
            history.removeAll { $0.fileURL != nil }
            if current?.fileURL != nil { current = nil }
            stopFollowingRun()
            lastLibraryFailure = nil
            index.adoptDirectory(library)
            await index.resumeAfterDirectoryChange()
            return warnings
        } catch {
            await index.resumeAfterDirectoryChange()
            throw error
        }
    }
}
