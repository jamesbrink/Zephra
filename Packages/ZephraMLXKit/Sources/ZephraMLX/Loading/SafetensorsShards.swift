import Foundation
import MLX

/// A component's `*.safetensors` files, and every tensor in them.
public enum SafetensorsShards {
    /// The shards in `directory`, sorted by name, which is the order every loader in the app
    /// reads a component in — so an index built over them and the dictionary read from them
    /// agree about which shard a tensor came from.
    public static func shards(in directory: URL) throws -> [URL] {
        let shards = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !shards.isEmpty else { throw SafetensorsShardsError.noShards(directory) }
        return shards
    }

    /// Every tensor in a component's shards, a name in two shards taken from the first.
    ///
    /// Arrays come back unevaluated: only each shard's header is parsed, and a tensor is read
    /// from the file into memory the first time it is evaluated, so nothing is resident until
    /// it is used.
    public static func weights(in directory: URL) throws -> [String: MLXArray] {
        var all: [String: MLXArray] = [:]
        for shard in try shards(in: directory) {
            all.merge(try MLX.loadArrays(url: shard)) { first, _ in first }
        }
        return all
    }
}
