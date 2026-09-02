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
        case .nothingPacked:
            "The quantization plan packed no layers, so the result would not load."
        }
    }
}
