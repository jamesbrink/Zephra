import Foundation
import MLX

/// Packs one component's safetensors shards, one tensor at a time.
///
/// Tensors are read out of the source shard one at a time (MLX loads each lazily, on its first
/// evaluation, with no mmap path), packed, evaluated, and
/// handed to the shard writer, so the only weights resident are the one being converted and
/// whatever the writer has yet to spill. That is what lets a 24 GB float32 transformer convert
/// in about 8 GB, and it is the property to preserve above all others in here.
///
/// Anything the component's rules leave alone — norms, embeddings, biases, whatever a family
/// declares — is copied across untouched, in its original dtype.
///
/// When the component names adapter files, each weight is merged with its low-rank update on the
/// way past, so a distilled variant costs one extra matmul per adapted tensor and no extra pass.
public struct ComponentQuantization {
    /// Which component this run converts, and how finely each of its tensors should be packed.
    public let component: QuantizedComponent
    /// Root of the full-precision snapshot.
    public let source: URL
    /// Root of the snapshot being written.
    public let destination: URL
    /// Bytes of packed tensors to hold before writing a shard.
    public let shardBudgetBytes: Int
    /// Where to report progress.
    public let note: (String) -> Void
    /// Asked before each tensor; throwing stops the conversion where it is. The largest tensor
    /// in any family here is a few hundred megabytes, so a stop lands within a second except
    /// across a shard flush.
    public let shouldContinue: () throws -> Void

    /// Prepares a conversion of one component.
    public init(
        component: QuantizedComponent,
        source: URL,
        destination: URL,
        shardBudgetBytes: Int,
        note: @escaping (String) -> Void,
        shouldContinue: @escaping () throws -> Void = {}
    ) {
        self.component = component
        self.source = source
        self.destination = destination
        self.shardBudgetBytes = shardBudgetBytes
        self.note = note
        self.shouldContinue = shouldContinue
    }

    /// Converts the component and returns a manifest entry per packed layer.
    public func run() throws -> [QuantizationManifest.Layer] {
        let sourceDirectory = source.appending(path: component.directoryName)
        guard FileManager.default.fileExists(
            atPath: sourceDirectory.path(percentEncoded: false))
        else {
            throw QuantizationError.missingComponent(
                name: component.directoryName, directory: sourceDirectory)
        }
        let shards = try Self.shards(in: sourceDirectory)
        guard !shards.isEmpty else {
            throw QuantizationError.noShards(
                name: component.directoryName, directory: sourceDirectory)
        }

        let writer = QuantizedShardWriter(
            directory: try emptiedOutputDirectory(), budgetBytes: shardBudgetBytes)

        let adapter =
            component.adapters.isEmpty ? nil : try LoRAAdapter(contentsOf: component.adapters)
        if let adapter {
            note("\(component.directoryName): merging \(adapter.count) adapted weights")
        }

        var packed: [(QuantizableWeight, QuantizationPrecision)] = []
        for (index, shard) in shards.enumerated() {
            note(
                "\(component.directoryName): reading \(shard.lastPathComponent) "
                    + "(\(index + 1) of \(shards.count))")
            packed += try convert(shard: shard, into: writer, adapter: adapter)
        }
        if let adapter, !adapter.unmatchedKeys.isEmpty {
            throw QuantizationError.unmatchedAdapterLayers(
                component: component.directoryName, keys: adapter.unmatchedKeys)
        }
        let shardOfTensor = try writer.finish(relativeTo: component.directoryName)
        note("\(component.directoryName): packed \(packed.count) layers")

        return try packed.map { weight, precision in
            guard let file = shardOfTensor[weight.weightKey] else {
                throw QuantizationError.unwrittenTensor(weight.weightKey)
            }
            return QuantizationManifest.Layer(
                name: weight.base,
                shape: [weight.outDim, weight.inDim],
                inDim: weight.inDim,
                outDim: weight.outDim,
                file: file,
                precision: precision,
                mode: "affine"
            )
        }
    }

    /// The component's output directory, with any shards a previous run left in it removed.
    ///
    /// A rerun writes a different number of shards, and one left behind still matches the glob
    /// the loader reads the component with, so it would be loaded alongside the new ones.
    private func emptiedOutputDirectory() throws -> URL {
        let directory = destination.appending(path: component.directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for stale in try Self.shards(in: directory) {
            try FileManager.default.removeItem(at: stale)
        }
        return directory
    }

    private static func shards(in directory: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
