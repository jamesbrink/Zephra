import Foundation

/// The `quantization.json` a locally built snapshot carries.
///
/// Its presence is what tells the loader the weights are packed. The top-level pair is only a
/// fallback: every layer states its own width, which is what lets a build hold the modulation
/// layers at eight bits while everything else is at four.
public struct QwenImageQuantizationManifest: Decodable {
    /// One packed layer.
    public struct Layer: Decodable {
        /// The module path the weights load into.
        public let name: String
        /// Bits per weight.
        public let bits: Int
        /// Weights sharing a scale.
        public let groupSize: Int

        enum CodingKeys: String, CodingKey {
            case name, bits
            case groupSize = "group_size"
        }
    }

    /// What to assume for a layer not listed.
    public let bits: Int
    /// What to assume for a layer not listed.
    public let groupSize: Int
    /// Every packed layer.
    public let layers: [Layer]

    enum CodingKeys: String, CodingKey {
        case bits, layers
        case groupSize = "group_size"
    }

    /// Reads the manifest at a snapshot's root, or nil when the snapshot is full precision.
    public static func read(from snapshot: URL) -> QwenImageQuantizationManifest? {
        guard let data = try? Data(contentsOf: snapshot.appending(path: "quantization.json"))
        else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// How a named layer was packed, falling back to the header when it is not listed.
    public func precision(of name: String) -> (bits: Int, groupSize: Int) {
        byName[name].map { ($0.bits, $0.groupSize) } ?? (bits, groupSize)
    }

    private var byName: [String: Layer] {
        Dictionary(layers.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
