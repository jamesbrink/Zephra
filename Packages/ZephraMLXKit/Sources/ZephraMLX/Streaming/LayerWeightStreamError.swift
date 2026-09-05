import Foundation

/// What can go wrong setting up or running a `LayerWeightStream`.
public enum LayerWeightStreamError: Error, Equatable, LocalizedError {
    /// A layer has a parameter the shards do not carry: the variant on disk is not the one
    /// the module tree was built for.
    case missingTensor(String)
    /// A pass opened the shards and found a tensor gone that the last pass had: the files
    /// changed under a running model.
    case tensorGone(String)

    public var errorDescription: String? {
        switch self {
        case .missingTensor(let name):
            "The weights on disk carry no tensor named \(name)."
        case .tensorGone(let name):
            "The tensor \(name) was there at load and is gone from the shards now."
        }
    }
}
