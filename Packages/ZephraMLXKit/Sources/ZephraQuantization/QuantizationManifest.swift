import Foundation

/// The `quantization.json` a quantized snapshot carries, in the shape the vendored
/// `ZImageQuantizationManifest` decodes.
///
/// Its presence is what makes the loader read packed shards at all. Every layer carries its own
/// `bits` and `group_size`, and the loader uses them for any layer it finds in `layers` by name.
/// The top-level pair is only the fallback for a layer it cannot find, which is how a
/// mixed-precision build stays loadable.
public struct QuantizationManifest: Encodable {
    /// One packed linear layer.
    public struct Layer: Encodable {
        /// The module path the loader will look this layer up by.
        public let name: String
        /// The original, unpacked shape, as `[outDim, inDim]`.
        public let shape: [Int]
        /// The layer's input width.
        public let inDim: Int
        /// The layer's output width.
        public let outDim: Int
        /// The shard the packed weight ended up in, relative to the snapshot root.
        public let file: String
        /// How this layer was packed. Written out per layer, always, so a mixed build describes
        /// itself layer by layer rather than leaning on the header.
        public let precision: QuantizationPrecision
        /// The packing scheme, always `affine` here.
        public let mode: String

        /// Creates one manifest entry.
        public init(
            name: String,
            shape: [Int],
            inDim: Int,
            outDim: Int,
            file: String,
            precision: QuantizationPrecision,
            mode: String
        ) {
            self.name = name
            self.shape = shape
            self.inDim = inDim
            self.outDim = outDim
            self.file = file
            self.precision = precision
            self.mode = mode
        }

        enum CodingKeys: String, CodingKey {
            case name, shape, bits, mode, file
            case inDim = "in_dim"
            case outDim = "out_dim"
            case groupSize = "group_size"
            case quantFile = "quant_file"
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(shape, forKey: .shape)
            try container.encode(inDim, forKey: .inDim)
            try container.encode(outDim, forKey: .outDim)
            try container.encode(file, forKey: .file)
            try container.encode(file, forKey: .quantFile)
            try container.encode(precision.bits, forKey: .bits)
            try container.encode(precision.groupSize, forKey: .groupSize)
            try container.encode(mode, forKey: .mode)
        }
    }

    /// The repository the full-precision weights came from.
    public let modelId: String?
    /// The revision of that repository.
    public let revision: String?
    /// What the loader assumes for a layer it cannot find in `layers` by name.
    public let fallback: QuantizationPrecision
    /// The packing scheme, always `affine` here.
    public let mode: String
    /// Every packed layer, across all components.
    public let layers: [Layer]

    /// Creates a manifest.
    public init(
        modelId: String?,
        revision: String?,
        fallback: QuantizationPrecision,
        mode: String,
        layers: [Layer]
    ) {
        self.modelId = modelId
        self.revision = revision
        self.fallback = fallback
        self.mode = mode
        self.layers = layers
    }

    enum CodingKeys: String, CodingKey {
        case revision, bits, mode, layers
        case modelId = "model_id"
        case groupSize = "group_size"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(modelId, forKey: .modelId)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encode(fallback.groupSize, forKey: .groupSize)
        try container.encode(fallback.bits, forKey: .bits)
        try container.encode(mode, forKey: .mode)
        try container.encode(layers, forKey: .layers)
    }

    /// The precision most of `layers` were packed at, or nil when nothing was packed.
    ///
    /// This is the honest header for a mixed build: the top level reaches only the layers a
    /// name lookup misses, so the value that covers the most layers is the one a miss most
    /// likely needed. Ties go to the precision that appears first, which is the transformer's.
    public static func commonestPrecision(across layers: [Layer]) -> QuantizationPrecision? {
        var order: [QuantizationPrecision] = []
        var tally: [QuantizationPrecision: Int] = [:]
        for layer in layers {
            if tally[layer.precision] == nil { order.append(layer.precision) }
            tally[layer.precision, default: 0] += 1
        }
        return order.max { tally[$0, default: 0] < tally[$1, default: 0] }
    }

    /// Writes the manifest to `quantization.json` inside a snapshot directory.
    public func write(into snapshot: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: snapshot.appending(path: "quantization.json"))
    }
}
