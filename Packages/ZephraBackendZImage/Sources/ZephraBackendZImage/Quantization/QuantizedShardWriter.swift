import Foundation
import MLX

/// Collects tensors and spills them to safetensors shards once they reach a byte budget.
///
/// The point is to never hold a whole component. A full-precision Z-Image transformer is
/// twenty-four gigabytes of float32, so quantizing it as one dictionary would need all of that
/// resident at once; writing a few gigabytes at a time keeps the process near the budget.
/// Shards are written under temporary names because safetensors convention puts the total shard
/// count in every file name, and that total is only known once the component is finished.
final class QuantizedShardWriter {
    private let directory: URL
    private let budgetBytes: Int
    private var pending: [String: MLXArray] = [:]
    private var pendingBytes = 0
    private var shardIndex = 0
    private var shardOfTensor: [String: Int] = [:]

    /// Prepares to write shards into `directory`, flushing whenever pending tensors exceed
    /// `budgetBytes`.
    init(directory: URL, budgetBytes: Int) {
        self.directory = directory
        self.budgetBytes = budgetBytes
    }

    /// Queues one evaluated tensor, flushing first if it would push the shard over budget.
    func add(_ name: String, _ array: MLXArray) throws {
        let size = array.shape.reduce(1, *) * array.dtype.size
        if pendingBytes > 0, pendingBytes + size > budgetBytes {
            try flush()
        }
        pending[name] = array
        pendingBytes += size
        shardOfTensor[name] = shardIndex
    }

    /// Writes anything still queued, renames every shard to its final `-of-` name, and returns
    /// the shard path each tensor landed in, relative to the component directory.
    func finish(relativeTo prefix: String) throws -> [String: String] {
        try flush()
        let total = shardIndex
        var finalNames: [Int: String] = [:]
        for index in 0..<total {
            let name = Self.shardName(index: index, total: total)
            try FileManager.default.moveItem(
                at: directory.appending(path: Self.temporaryName(index: index)),
                to: directory.appending(path: name)
            )
            finalNames[index] = "\(prefix)/\(name)"
        }
        return shardOfTensor.compactMapValues { finalNames[$0] }
    }

    /// Writes the queued tensors as one shard and releases them.
    private func flush() throws {
        guard !pending.isEmpty else { return }
        let url = directory.appending(path: Self.temporaryName(index: shardIndex))
        try MLX.save(arrays: pending, metadata: [:], url: url)
        pending.removeAll(keepingCapacity: false)
        pendingBytes = 0
        shardIndex += 1
        Memory.clearCache()
    }

    /// Shards are staged under this name and renamed at the end. The extension has to stay
    /// `.safetensors`, because that is how `MLX.save` picks its format.
    private static func temporaryName(index: Int) -> String {
        String(format: "staging-%05d.safetensors", index + 1)
    }

    private static func shardName(index: Int, total: Int) -> String {
        total == 1
            ? "model.safetensors"
            : String(format: "model-%05d-of-%05d.safetensors", index + 1, total)
    }
}
