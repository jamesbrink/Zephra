import Foundation

/// The `quantization.json` a quantized snapshot carries, in the shape the vendored
/// `ZImageQuantizationManifest` decodes.
///
/// Its presence is what makes the loader read packed shards at all. The top-level `bits` and
/// `group_size` are the fallback the loader applies to any layer it cannot find by name; the
/// per-layer values override them, which is how a mixed-precision build stays loadable.
struct QuantizationManifest: Encodable {
    /// One packed linear layer.
    struct Layer: Encodable {
        /// The module path the loader will look this layer up by.
        let name: String
        /// The original, unpacked shape, as `[outDim, inDim]`.
        let shape: [Int]
        /// The layer's input width.
        let inDim: Int
        /// The layer's output width.
        let outDim: Int
        /// The shard the packed weight ended up in, relative to the snapshot root.
        let file: String
        /// Bits per weight for this layer.
        let bits: Int
        /// Weights per scale for this layer.
        let groupSize: Int
        /// The packing scheme, always `affine` here.
        let mode: String

        enum CodingKeys: String, CodingKey {
            case name, shape, bits, mode, file
            case inDim = "in_dim"
            case outDim = "out_dim"
            case groupSize = "group_size"
            case quantFile = "quant_file"
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(shape, forKey: .shape)
            try container.encode(inDim, forKey: .inDim)
            try container.encode(outDim, forKey: .outDim)
            try container.encode(file, forKey: .file)
            try container.encode(file, forKey: .quantFile)
            try container.encode(bits, forKey: .bits)
            try container.encode(groupSize, forKey: .groupSize)
            try container.encode(mode, forKey: .mode)
        }
    }

    /// The repository the full-precision weights came from.
    let modelId: String?
    /// The revision of that repository.
    let revision: String?
    /// The group size to assume for a layer the loader cannot find by name.
    let groupSize: Int
    /// The bit width to assume for a layer the loader cannot find by name.
    let bits: Int
    /// The packing scheme, always `affine` here.
    let mode: String
    /// Every packed layer, across all components.
    let layers: [Layer]

    enum CodingKeys: String, CodingKey {
        case revision, bits, mode, layers
        case modelId = "model_id"
        case groupSize = "group_size"
    }

    /// Writes the manifest to `quantization.json` inside a snapshot directory.
    func write(into snapshot: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: snapshot.appending(path: "quantization.json"))
    }
}
