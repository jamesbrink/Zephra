import Foundation
import MLX

extension ComponentQuantization {
    /// Reads one source shard and writes its tensors, packed or verbatim, to `writer`.
    func convert(
        shard: URL, into writer: QuantizedShardWriter
    ) throws -> [(QuantizableWeight, QuantizationPrecision)] {
        // Mapped, not read: the arrays below are views into the file until they are evaluated.
        let tensors = try MLX.loadArrays(url: shard)
        var packed: [(QuantizableWeight, QuantizationPrecision)] = []
        // In file order, so the mapped shard is read once from front to back.
        for entry in try SafeTensorsHeader(contentsOf: shard).entries {
            try shouldContinue()
            guard let tensor = tensors[entry.name] else {
                throw QuantizationError.unreadableShard(
                    shard, reason: "header names \(entry.name) but the file does not hold it")
            }
            // Some tensors are not in the build at all: an unloaded vision tower is gigabytes
            // that would otherwise be copied for nothing.
            if component.omits(entry.name) { continue }
            let sourceType = tensor.dtype
            // Policy first: the group size it names is what divisibility is tested against.
            guard let precision = component.precision(for: entry.name),
                let weight = QuantizableWeight(
                    name: entry.name, shape: entry.shape, groupSize: precision.groupSize)
            else {
                // The source's own dtype: a copied tensor should come out the width it
                // went in.
                let verbatim = tensor.asType(sourceType)
                MLX.eval(verbatim)
                try writer.add(entry.name, verbatim)
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
}
