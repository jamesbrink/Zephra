import Foundation

/// What can go wrong while turning a full-precision snapshot into a quantized one.
public enum QuantizationError: Error, LocalizedError, Equatable {
    /// MLX packs four or eight bits per weight and nothing else.
    case unsupportedBits(Int)
    /// MLX shares one scale across 32, 64, or 128 weights and nothing else.
    case unsupportedGroupSize(Int)
    /// The source snapshot has no directory for a component that must be quantized.
    case missingComponent(name: String, directory: URL)
    /// The component directory exists but holds no safetensors shards.
    case noShards(name: String, directory: URL)
    /// A shard's header could not be read, so nothing in it can be placed.
    case unreadableShard(URL, reason: String)
    /// The plan packed nothing at all, so there is no manifest to write and no build to load.
    case nothingPacked
    /// A packed tensor was handed to the shard writer and no shard came back holding it.
    case unwrittenTensor(String)
    /// An adapter file holds one half of a low-rank update and not the other.
    case incompleteAdapterLayer(String)
    /// An adapter's update is not the shape of the weight it claims to modify.
    case adapterShapeMismatch(String, adapter: [Int], weight: [Int])
    /// An adapter names weights the component being packed does not have, so the distillation
    /// it encodes would be silently half-applied.
    case unmatchedAdapterLayers(component: String, keys: [String])
    /// The volume the build would be written to cannot hold it. Checked before anything is
    /// read, because a component that ran out of disk half way reads as a snapshot to a loader.
    case notEnoughSpace(needed: Int64, free: Int64)

    public var errorDescription: String? {
        switch self {
        case .unsupportedBits(let bits):
            "\(bits)-bit quantization is not supported; use 4 or 8."
        case .unsupportedGroupSize(let size):
            "Group size \(size) is not supported; use 32, 64, or 128."
        case .missingComponent(let name, let directory):
            "The source snapshot has no \(name) directory at \(directory.path(percentEncoded: false))."
        case .noShards(let name, let directory):
            "No .safetensors shards in \(name) at \(directory.path(percentEncoded: false))."
        case .unreadableShard(let url, let reason):
            "Could not read \(url.lastPathComponent): \(reason)."
        case .unwrittenTensor(let key):
            "\(key) was packed but landed in no shard; the build cannot be loaded."
        case .nothingPacked:
            "The quantization plan packed no layers, so the result would not load."
        case .incompleteAdapterLayer(let key):
            "The adapter has only one of the two factors for \(key), so it cannot be merged."
        case .adapterShapeMismatch(let key, let adapter, let weight):
            "The adapter's update for \(key) is \(adapter) but the weight is \(weight)."
        case .unmatchedAdapterLayers(let component, let keys):
            """
            The adapter names \(keys.count) weights \(component) has not got, such as \
            \(keys.prefix(3).joined(separator: ", ")). Merging it would apply part of the \
            distillation and not the rest.
            """
        case .notEnoughSpace(let needed, let free):
            """
            Building this model needs about \(Self.gigabytes(needed)) free and the disk has \
            \(Self.gigabytes(free)).
            """
        }
    }

    /// Bytes as gigabytes to one decimal place. A copy of `ZephraCore.ByteCount` on purpose:
    /// the packer is deliberately free of every Zephra dependency, and one line of arithmetic
    /// is a smaller price than a layer crossing.
    private static func gigabytes(_ bytes: Int64) -> String {
        let tenths = Int((Double(bytes) / 100_000_000).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10) GB" : "\(tenths / 10).\(tenths % 10) GB"
    }
}
