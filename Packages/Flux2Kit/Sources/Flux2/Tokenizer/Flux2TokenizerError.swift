import Foundation

/// What can go wrong loading the tokenizer from a snapshot.
public enum Flux2TokenizerError: Error, LocalizedError, Equatable {
    /// A file the tokenizer is read from is not in the snapshot.
    case missingFile(URL)
    /// A file is there but the tokenizer could not be built from it, for the reason given.
    case malformed(URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let url):
            "The snapshot has no \(url.lastPathComponent)."
        case .malformed(let url, let reason):
            "\(url.lastPathComponent) could not be read as a tokenizer: \(reason)"
        }
    }
}
