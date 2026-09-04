import Foundation

/// Whether a snapshot directory is a finished download, decided from the disk alone.
///
/// A download that was stopped half-way looks a lot like one that finished: the small files
/// arrive first, so the configs are there, and so is the autoencoder. Three things tell them
/// apart. The hub client leaves an `.incomplete` file beside its bookkeeping for every file it
/// is still transferring. A sharded component ships a `*.safetensors.index.json` naming every
/// shard, so a shard that never started is a name with nothing beside it. And a snapshot with a
/// config and no weights at all was never more than a listing.
public nonisolated enum HubSnapshotCheck {
    /// Whether `snapshot` holds a config, some weights, every shard its indexes name, and no
    /// transfer still in flight.
    public static func isComplete(_ snapshot: URL) -> Bool {
        guard HubCache.isDirectory(snapshot), hasConfig(snapshot) else { return false }
        let entries = contents(of: snapshot)
        let components = [snapshot] + entries.filter(HubCache.isDirectory)
        let weights = components.flatMap(contents).filter { $0.pathExtension == "safetensors" }
        guard !weights.isEmpty else { return false }
        guard components.allSatisfy(shardsArePresent) else { return false }
        return incompleteFiles(in: snapshot).isEmpty
    }

    /// The files a transfer left unfinished under `snapshot`, in the flat layout's bookkeeping
    /// directory. Empty for the `hf` layout, which keeps its partial blobs elsewhere.
    public static func incompleteFiles(in snapshot: URL) -> [URL] {
        let bookkeeping = snapshot.appending(path: ".cache/huggingface/download")
        guard HubCache.isDirectory(bookkeeping),
              let walk = FileManager.default.enumerator(
                at: bookkeeping, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "incomplete" }
    }

    private static func hasConfig(_ snapshot: URL) -> Bool {
        ["model_index.json", "config.json"].contains {
            FileManager.default.fileExists(
                atPath: snapshot.appending(path: $0).path(percentEncoded: false))
        }
    }

    /// Whether every shard the component's index names is beside it. A component with no
    /// index has nothing to promise.
    private static func shardsArePresent(in component: URL) -> Bool {
        let indexes = contents(of: component).filter {
            $0.lastPathComponent.hasSuffix(".safetensors.index.json")
        }
        return indexes.allSatisfy { index in
            shards(named: index).allSatisfy { shard in
                FileManager.default.fileExists(
                    atPath: component.appending(path: shard).path(percentEncoded: false))
            }
        }
    }

    /// The distinct file names an index's `weight_map` points at. An index that cannot be read
    /// names nothing, so it cannot fail the check; the loader will say what is wrong with it.
    private static func shards(named index: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: index),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map = json["weight_map"] as? [String: String]
        else { return [] }
        return Set(map.values)
    }

    private static func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    }
}
