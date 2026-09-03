import Foundation

/// What can go wrong assembling the tokenizer from a snapshot.
public enum QwenImageTokenizerError: Error, LocalizedError, Equatable {
    /// A file the tokenizer is assembled from is not in the snapshot.
    case missingFile(URL)
    /// A file is there but is not the JSON it should be.
    case malformed(URL)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let url):
            "The snapshot has no \(url.lastPathComponent)."
        case .malformed(let url):
            "\(url.lastPathComponent) is not in the expected format."
        }
    }
}
