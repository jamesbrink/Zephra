import Foundation

/// Where a model's weights come from.
public enum ModelSource: Hashable, Sendable {
    /// A Hugging Face repository, fetched into the local hub cache on first use.
    /// `filePatterns` are the globs worth downloading from it.
    case huggingFace(repoID: String, revision: String, filePatterns: [String])
    /// A directory already on this Mac laid out like a hub snapshot, such as a variant the
    /// user quantized locally.
    case localDirectory(URL)

    /// Whether using this source may need the network.
    public var requiresDownload: Bool {
        switch self {
        case .huggingFace: true
        case .localDirectory: false
        }
    }
}
