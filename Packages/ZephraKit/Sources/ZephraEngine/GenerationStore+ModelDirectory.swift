import Foundation
import ZephraCore
import ZephraSnapshot

extension GenerationStore {
    /// A folder change may stop preparation, but never discards queued or generating work.
    public var canChangeModelDirectory: Bool {
        !isChangingModelDirectory && !isChangingImageDirectory && !isDraining && !isUpscaling && queue.isEmpty && state != .cancelling
    }

    public var isChangingModelDirectory: Bool { modelDirectoryProgress != nil }

    /// Stops preparation before changing its destination, optionally moving one old root.
    /// The caller persists the returned location only after this operation succeeds.
    public func changeModelDirectory(to target: ModelLocations, moving source: URL? = nil) async throws -> [String] {
        guard canChangeModelDirectory else {
            throw ModelDirectoryError("Wait for generation and queued work to finish before changing the models folder.")
        }
        modelDirectoryProgress = "Preparing models folder…"
        defer { modelDirectoryProgress = nil }
        let pendingSwitch = switchTask
        let pendingLoad = bootstrapTask
        let interrupted = state.isBusy || isSwappingModel
        pendingSwitch?.cancel()
        pendingLoad?.cancel()
        await pendingSwitch?.value
        await pendingLoad?.value
        isSwappingModel = false
        if source != nil || interrupted {
            await inference?.unload()
            loadedDescriptor = nil
            loadedDirectory = nil
            transition(to: .idle)
        }
        let updates = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let progressTask = Task {
            for await message in updates.stream { modelDirectoryProgress = message }
        }
        let operation = Task.detached(priority: .utility) {
            defer { updates.continuation.finish() }
            if let source {
                return try ModelMigration(from: source, to: target.root).run { message in
                    updates.continuation.yield(message)
                }
            }
            try ModelDirectoryAccess.prepare(target.root)
            return [String]()
        }
        // Detached disk work must settle before releasing the gate, even if the view closes.
        let outcome = await operation.result
        await progressTask.value
        let warnings = try outcome.get()
        locations = target
        await inference?.setLocations(target)
        return warnings
    }
}
