import Foundation

/// Packing a release into the variant this Mac loads, safely, from the inference executor.
///
/// The quantizer itself does not care where its output goes; this does, because the app builds
/// into a folder a loader will look in the moment the build stops. So the work happens in a
/// sibling `.partial` directory and is renamed on success — a stopped or crashed build never
/// leaves a directory the loader would accept — and the directory is removed when the build
/// fails, because gigabytes nobody asked to keep are worse than starting over.
///
/// It refuses before writing when the volume cannot take the result. A partial component reads
/// as a snapshot to a loader, so running out of disk half way through is the one failure that
/// produces a model that loads and is wrong.
public enum SnapshotBuild {
    /// Bytes to buffer before spilling a shard: the packer's default, or an eighth of the
    /// machine's memory on a Mac where the default would not leave room for the app.
    public static var shardBudgetBytes: Int {
        min(
            SnapshotQuantizer.defaultShardBudgetBytes,
            Int(ProcessInfo.processInfo.physicalMemory) / 8)
    }

    /// Packs `release` into `destination` following `plan`, and returns `destination`.
    ///
    /// - Parameters:
    ///   - freeSpaceBytes: What the build is expected to write, checked against the volume
    ///     before anything is read. The descriptor's own `builtBytes`, in practice.
    ///   - note: One line of the packer's log at a time, which is what a family turns into
    ///     progress with a `BuildTally`.
    ///   - shouldContinue: Called before each tensor; throw from it to stop the build.
    public static func pack(
        release: URL,
        into destination: URL,
        plan: QuantizationPlan,
        sourceName: String,
        freeSpaceBytes: Int64,
        note: @escaping (String) -> Void,
        shouldContinue: @escaping () throws -> Void,
        finalize: (URL) throws -> Void = { _ in }
    ) throws -> URL {
        let partial = destination.deletingLastPathComponent()
            .appending(
                path: destination.lastPathComponent + ".partial", directoryHint: .isDirectory)
        // Neither the directory replaced at the end nor the partial emptied at the start may
        // touch the release, or the build destroys what it reads. Checked before either is.
        try SnapshotQuantizer.requireDisjoint(source: release, destination: destination)
        try SnapshotQuantizer.requireDisjoint(source: release, destination: partial)
        // What a crashed build left behind is removed before the volume is measured: on a
        // nearly full disk it is the very thing standing in the way.
        try? FileManager.default.removeItem(at: partial)
        try requireFreeSpace(near: destination, bytes: freeSpaceBytes)
        do {
            try SnapshotQuantizer.quantize(
                source: release,
                destination: partial,
                plan: plan,
                sourceName: sourceName,
                shardBudgetBytes: shardBudgetBytes,
                note: note,
                shouldContinue: shouldContinue
            )
            try finalize(partial)
            // The replacement is inside the same cleanup: a destination that will not go, or
            // a move that fails, must not leave gigabytes of finished partial behind either.
            let files = FileManager.default
            if files.fileExists(atPath: destination.path(percentEncoded: false)) {
                try files.removeItem(at: destination)
            }
            try files.moveItem(at: partial, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        return destination
    }

    /// Refuses when the volume holding `directory` cannot take roughly `bytes` more.
    private static func requireFreeSpace(near directory: URL, bytes: Int64) throws {
        let parent = directory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let values = try parent.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values.volumeAvailableCapacityForImportantUsage, free < bytes
        else { return }
        throw QuantizationError.notEnoughSpace(needed: bytes, free: free)
    }
}
