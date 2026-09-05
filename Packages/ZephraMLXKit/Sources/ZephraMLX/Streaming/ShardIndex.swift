import Foundation
import MLX

/// Which shard each tensor of a component lives in, and how big it is, without reading any
/// of it.
///
/// `MLX.loadArrays` parses a shard's header and hands back arrays that are not read until they
/// are evaluated, so building this costs one header parse per shard. The arrays themselves are
/// dropped: keeping them would keep every shard's file open, and evaluating one later would
/// materialise the tensor into the very dictionary a stream needs to stay lazy.
public struct ShardIndex: Sendable {
    /// Where one tensor is and what it costs to read.
    public struct Entry: Hashable, Sendable {
        public let shard: URL
        public let bytes: Int
    }

    /// The shards, in the order the loader reads them.
    public let shards: [URL]
    /// Every tensor the shards hold, by the name the checkpoint gives it.
    public let entries: [String: Entry]

    /// Indexes `shards`, which are read in the order given. A name in two shards is taken
    /// from the first, the way the loader merges them.
    public init(shards: [URL]) throws {
        var entries: [String: Entry] = [:]
        for shard in shards {
            for (name, array) in try MLX.loadArrays(url: shard) where entries[name] == nil {
                entries[name] = Entry(shard: shard, bytes: array.nbytes)
            }
        }
        self.shards = shards
        self.entries = entries
    }

    /// Indexes every `*.safetensors` in `directory`, sorted by name, which is the order every
    /// loader in the app reads a component's shards in.
    public init(directory: URL) throws {
        let shards = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try self.init(shards: shards)
    }

    /// Bytes the named tensors occupy on disk; a name not in the index counts nothing.
    public func bytes(ofKeys keys: some Sequence<String>) -> Int {
        keys.reduce(0) { $0 + (entries[$1]?.bytes ?? 0) }
    }

    /// The shards holding any of `keys`, in the index's order.
    public func shards(holding keys: some Sequence<String>) -> [URL] {
        let wanted = Set(keys.compactMap { entries[$0]?.shard })
        return shards.filter { wanted.contains($0) }
    }
}
