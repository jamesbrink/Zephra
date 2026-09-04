import Foundation

/// Where a model's weights come from.
public enum ModelSource: Hashable, Sendable {
    /// A Hugging Face repository, fetched into the folder Zephra keeps models in on first use.
    /// `filePatterns` are the globs worth downloading from it.
    case huggingFace(repoID: String, revision: String, filePatterns: [String])
    /// A directory already on this Mac laid out like a hub snapshot.
    ///
    /// No catalog entry uses this any more: every variant Zephra ships knowledge of names the
    /// release it is packed from, so the app can fetch and build it without the command line.
    /// The case stays because a descriptor is not only the catalog — `ZephraBench` points one
    /// at a directory to measure, and a variant built by hand somewhere else is still a model
    /// the backends can be asked to load.
    case localDirectory(URL)

    /// Whether using this source may need the network.
    public var requiresDownload: Bool {
        switch self {
        case .huggingFace: true
        case .localDirectory: false
        }
    }
}
