import Foundation

/// The `quantization.json` a locally built snapshot carries.
///
/// Its presence is what tells a loader the weights are packed. The top-level pair is only a
/// fallback: every layer states its own width, which is what lets a build hold some layers at
/// eight bits while everything else is at four. One reader for every family, because the
/// packer writes one format; the names inside are whatever the family's plan wrote, and the
/// family maps its module paths back to them with `checkpointName` when the two differ.
public struct PackedSnapshotManifest: Decodable {
    /// One packed layer.
    public struct Layer: Decodable {
        /// The checkpoint name of the layer, without `.weight`.
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

    // Built once at decode: the loader asks for every leaf of a sixty-block tree, and a
    // dictionary rebuilt per lookup made that quadratic in the layer count.
    private let byName: [String: Layer]

    enum CodingKeys: String, CodingKey {
        case bits, layers
        case groupSize = "group_size"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bits = try container.decode(Int.self, forKey: .bits)
        groupSize = try container.decode(Int.self, forKey: .groupSize)
        layers = try container.decode([Layer].self, forKey: .layers)
        byName = Dictionary(layers.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Reads the manifest at a snapshot's root: nil when the snapshot has none, which is what
    /// a full-precision snapshot looks like, and an error when it has one that cannot be read.
    ///
    /// A broken manifest is never taken for a missing one. Reading it as "unpacked" loads a
    /// packed shard into an unpacked tree and fails a component later with a shape error that
    /// names neither the file nor the reason.
    public static func read(from snapshot: URL) throws -> PackedSnapshotManifest? {
        let url = snapshot.appending(path: "quantization.json")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch {
            throw PackedSnapshotError.malformedManifest(url, reason: String(describing: error))
        }
    }

    /// How a named layer was packed, falling back to the header when it is not listed.
    public func precision(of name: String) -> (bits: Int, groupSize: Int) {
        byName[name].map { ($0.bits, $0.groupSize) } ?? (bits, groupSize)
    }
}
