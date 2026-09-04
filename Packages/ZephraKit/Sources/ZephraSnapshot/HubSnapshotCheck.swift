import Foundation

/// Whether a snapshot directory is a finished download, decided from the disk alone.
///
/// A download that was stopped half-way looks a lot like one that finished: the small files
/// arrive first, so the configs are there, and so is the autoencoder. Four things tell them
/// apart. `model_index.json` names every component the pipeline loads, so a component
/// directory that never arrived is a name with nothing behind it. A component with a
/// `config.json` is a module with weights, so it needs at least one safetensors file. A
/// sharded module's files are numbered `-00001-of-00002`, and a `*.safetensors.index.json`
/// names every shard, so a shard that never started is a number with nothing beside it. And
/// the hub client leaves an `.incomplete` file for every file it is still transferring.
public nonisolated enum HubSnapshotCheck {
    /// Whether `snapshot` holds every component its index names, weights for each module,
    /// every shard those weights are cut into, and no transfer still in flight.
    ///
    /// Without a readable index there is no list of components to hold the snapshot to, so the
    /// rule is what can still be checked: a config, weights somewhere at the top or one level
    /// down, and every shard those weights count up to.
    public static func isComplete(_ snapshot: URL) -> Bool {
        guard HubCache.isDirectory(snapshot), incompleteFiles(in: snapshot).isEmpty else {
            return false
        }
        let index = snapshot.appending(path: "model_index.json")
        if let components = components(namedIn: index) {
            return !components.isEmpty && components.allSatisfy { name in
                let directory = snapshot.appending(path: name, directoryHint: .isDirectory)
                return HubCache.isDirectory(directory) && !contents(of: directory).isEmpty
                    && (!hasConfig(directory) || hasWeights(directory))
                    && shardsAreComplete(in: directory)
            }
        }
        guard hasConfig(snapshot) || FileManager.default.fileExists(atPath: index.path(percentEncoded: false))
        else { return false }
        let modules = [snapshot] + contents(of: snapshot).filter(HubCache.isDirectory)
        return modules.contains(where: hasWeights) && modules.allSatisfy(shardsAreComplete)
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

    /// The component directories a diffusers `model_index.json` names: every key whose value
    /// is a `[library, class]` pair. Nil when there is no index, or it cannot be read.
    private static func components(namedIn index: URL) -> [String]? {
        guard let data = try? Data(contentsOf: index),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json.compactMap { key, value in
            (value as? [Any])?.count == 2 ? key : nil
        }.sorted()
    }

    private static func hasConfig(_ directory: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: directory.appending(path: "config.json").path(percentEncoded: false))
    }

    private static func hasWeights(_ module: URL) -> Bool {
        contents(of: module).contains { $0.pathExtension == "safetensors" }
    }

    /// Whether every shard the module's index names, and every shard its file names count
    /// up to, is there. Vacuously true for a module that is not sharded.
    private static func shardsAreComplete(in module: URL) -> Bool {
        let files = contents(of: module).map(\.lastPathComponent)
        let indexed = files.filter { $0.hasSuffix(".safetensors.index.json") }
            .flatMap { shards(named: module.appending(path: $0)) }
        let numbered = ShardName.expected(among: files)
        return Set(indexed).union(numbered).allSatisfy(files.contains)
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
