import Foundation

/// A component directory with nothing to load.
public enum SafetensorsShardsError: Error, LocalizedError, Equatable {
    /// No `*.safetensors` under the directory at all.
    case noShards(URL)

    public var errorDescription: String? {
        switch self {
        case .noShards(let directory):
            "No *.safetensors in \(directory.path(percentEncoded: false))."
        }
    }
}
