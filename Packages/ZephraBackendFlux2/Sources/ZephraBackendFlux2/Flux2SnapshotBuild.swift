import Foundation
import ZephraCore
import ZephraQuantization

/// Packing the release into the variant this Mac loads, on the inference executor.
///
/// The only file in the backend that touches the quantizer. It writes into a sibling `.partial`
/// directory and renames on success, so a build that is stopped never leaves a directory the
/// loader would accept; and it refuses before writing when the volume cannot hold the result,
/// because a partial component looks like a snapshot to the loader.
enum Flux2SnapshotBuild {
    /// Bytes to buffer before spilling a shard: the packer's default, or an eighth of the
    /// machine's memory on a Mac where the default would not leave room for the app.
    static var shardBudgetBytes: Int {
        min(SnapshotQuantizer.defaultShardBudgetBytes, Int(ProcessInfo.processInfo.physicalMemory) / 8)
    }

    /// Packs `release` into `destination` at `quantization`, reporting one event per note.
    static func pack(
        release: URL,
        into destination: URL,
        sourceName: String,
        quantization: Quantization,
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) throws -> URL {
        let bits = quantization == .int8 ? 8 : 4
        let plan = try Flux2QuantizationPlan.plan(bits: bits, groupSize: 64)
        try requireFreeSpace(near: destination, bytes: 6_000_000_000 * Int64(bits) / 4)

        let partial = destination.deletingLastPathComponent()
            .appending(path: destination.lastPathComponent + ".partial", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: partial)
        let progress = Flux2BuildProgress(plan: plan, report: onProgress)
        try SnapshotQuantizer.quantize(
            source: release,
            destination: partial,
            plan: plan,
            sourceName: sourceName,
            shardBudgetBytes: shardBudgetBytes,
            note: { progress.note($0) },
            shouldContinue: { try Task.checkCancellation() }
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }

    /// Refuses when the volume cannot take roughly `bytes` more.
    private static func requireFreeSpace(near directory: URL, bytes: Int64) throws {
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let values = try directory.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values.volumeAvailableCapacityForImportantUsage, free < bytes else { return }
        throw BackendError.loadFailed(
            "Building this model needs about \(ByteCount.gigabytes(bytes)) free and the disk has \(ByteCount.gigabytes(free)).")
    }
}
