import Foundation
import ZephraMLX

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

    /// Reads the manifest at a snapshot's root: nil when the snapshot has none, which is what
    /// a full-precision snapshot looks like, and an error when it has one that cannot be read.
    ///
    /// A broken manifest is never taken for a missing one. Reading it as "unpacked" loads a
    /// packed shard into an unpacked tree and fails a component later with a shape error that
    /// names neither the file nor the reason. (A copy of the other kit's reader; M8 of the
    /// audit remediation merges the two into `ZephraMLX`.)
    public static func read(from snapshot: URL) throws -> QwenImageQuantizationManifest? {
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

    private var byName: [String: Layer] {
        Dictionary(layers.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
