import Foundation
import MLX
import ZImage

/// Packs one component's safetensors shards, one tensor at a time.
///
/// Tensors are read straight out of the memory-mapped source shard, packed, evaluated, and
/// handed to the shard writer, so the only weights resident are the one being converted and
/// whatever the writer has yet to spill. Anything the loader does not expect packed — norms,
/// embeddings, biases, the two dictionary-keyed submodules — is copied across untouched, in its
/// original dtype, exactly as the reference eight-bit export does.
struct ComponentQuantization {
    /// Which component this run converts.
    let component: QuantizedComponent
    /// How hard to squeeze it.
    let precision: QuantizationPrecision
    /// Root of the full-precision snapshot.
    let source: URL
    /// Root of the snapshot being written.
    let destination: URL
    /// Bytes of packed tensors to hold before writing a shard.
    let shardBudgetBytes: Int
    /// Where to report progress.
    let note: (String) -> Void

    /// Converts the component and returns a manifest entry per packed layer.
    func run() throws -> [QuantizationManifest.Layer] {
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

        var packed: [QuantizableWeight] = []
        for (index, shard) in shards.enumerated() {
            note(
                "\(component.directoryName): reading \(shard.lastPathComponent) "
                    + "(\(index + 1) of \(shards.count))")
            packed += try convert(shard: shard, into: writer)
        }
        let shardOfTensor = try writer.finish(relativeTo: component.directoryName)
        note("\(component.directoryName): packed \(packed.count) layers at \(precision.summary)")

        return packed.map { weight in
            QuantizationManifest.Layer(
                name: component.manifestName(forWeightBase: weight.base),
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
        -> [QuantizableWeight]
    {
        let reader = try SafeTensorsReader(fileURL: shard)
        var packed: [QuantizableWeight] = []
        // In file order, so the mapped shard is read once from front to back.
        for metadata in reader.allMetadata().sorted(by: { $0.dataOffset < $1.dataOffset }) {
            let tensor = try reader.tensor(named: metadata.name)
            guard
                let weight = QuantizableWeight(
                    name: metadata.name, shape: metadata.shape, groupSize: precision.groupSize)
            else {
                MLX.eval(tensor)
                try writer.add(metadata.name, tensor)
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
            packed.append(weight)
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
