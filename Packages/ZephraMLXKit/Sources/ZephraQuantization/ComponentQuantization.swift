import Foundation
import MLX

/// Packs one component's safetensors shards, one tensor at a time.
///
/// Tensors are read straight out of the memory-mapped source shard, packed, evaluated, and
/// handed to the shard writer, so the only weights resident are the one being converted and
/// whatever the writer has yet to spill. That is what lets a 24 GB float32 transformer convert
/// in about 8 GB, and it is the property to preserve above all others in here.
///
/// Anything the component's rules leave alone — norms, embeddings, biases, whatever a family
/// declares — is copied across untouched, in its original dtype.
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

    /// Prepares a conversion of one component.
    public init(
        component: QuantizedComponent,
        source: URL,
        destination: URL,
        shardBudgetBytes: Int,
        note: @escaping (String) -> Void
    ) {
        self.component = component
        self.source = source
        self.destination = destination
        self.shardBudgetBytes = shardBudgetBytes
        self.note = note
    }

    /// Converts the component and returns a manifest entry per packed layer.
    public func run() throws -> [QuantizationManifest.Layer] {
        let files = FileManager.default
        let sourceDirectory = source.appending(path: component.directoryName)
        guard files.fileExists(atPath: sourceDirectory.path(percentEncoded: false)) else {
            throw QuantizationError.missingComponent(
                name: component.directoryName, directory: sourceDirectory)
        }
        let shards = try Self.shards(in: sourceDirectory)
        guard !shards.isEmpty else {
            throw QuantizationError.noShards(
                name: component.directoryName, directory: sourceDirectory)
        }

        let outputDirectory = destination.appending(path: component.directoryName)
        try files.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        // A rerun writes a different number of shards, so clear the old ones out. Left behind,
        // they would still match the glob the loader reads the component with.
        for stale in try Self.shards(in: outputDirectory) {
            try files.removeItem(at: stale)
        }
        let writer = QuantizedShardWriter(
            directory: outputDirectory, budgetBytes: shardBudgetBytes)

        var packed: [(QuantizableWeight, QuantizationPrecision)] = []
        for (index, shard) in shards.enumerated() {
            note(
                "\(component.directoryName): reading \(shard.lastPathComponent) "
                    + "(\(index + 1) of \(shards.count))")
            packed += try convert(shard: shard, into: writer)
        }
        let shardOfTensor = try writer.finish(relativeTo: component.directoryName)
        note("\(component.directoryName): packed \(packed.count) layers")

        return packed.map { weight, precision in
            QuantizationManifest.Layer(
                name: weight.base,
                shape: [weight.outDim, weight.inDim],
                inDim: weight.inDim,
                outDim: weight.outDim,
                file: shardOfTensor[weight.weightKey] ?? "",
                precision: precision,
                mode: "affine"
            )
        }
    }

    /// Reads one source shard and writes its tensors, packed or verbatim, to `writer`.
    private func convert(shard: URL, into writer: QuantizedShardWriter) throws
        -> [(QuantizableWeight, QuantizationPrecision)]
    {
        // Mapped, not read: the arrays below are views into the file until they are evaluated.
        let tensors = try MLX.loadArrays(url: shard)
        var packed: [(QuantizableWeight, QuantizationPrecision)] = []
        // In file order, so the mapped shard is read once from front to back.
        for entry in try SafeTensorsHeader(contentsOf: shard).entries {
            guard let tensor = tensors[entry.name] else {
                throw QuantizationError.unreadableShard(
                    shard, reason: "header names \(entry.name) but the file does not hold it")
            }
            // Some tensors are not in the build at all: an unloaded vision tower is gigabytes
            // that would otherwise be copied for nothing.
            if component.omits(entry.name) { continue }
            // Policy first: the group size it names is what divisibility is tested against.
            guard let precision = component.precision(for: entry.name),
                let weight = QuantizableWeight(
                    name: entry.name, shape: entry.shape, groupSize: precision.groupSize)
            else {
                MLX.eval(tensor)
                try writer.add(entry.name, tensor)
                continue
            }
            // Float32 in, so the scales and biases come out float32 and match the reference
            // export. The transformer is cast back to bfloat16 by the loader.
            let (values, scales, biases) = MLX.quantized(
                tensor.asType(.float32),
                groupSize: precision.groupSize,
                bits: precision.bits,
                mode: .affine
            )
            MLX.eval([values, scales, biases].compactMap { $0 })
            try writer.add(weight.weightKey, values)
            try writer.add(weight.scalesKey, scales)
            if let biases {
                try writer.add(weight.biasesKey, biases)
            }
            packed.append((weight, precision))
        }
        return packed
    }

    private static func shards(in directory: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
