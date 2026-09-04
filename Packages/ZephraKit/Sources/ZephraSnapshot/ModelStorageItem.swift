import Foundation
import ZephraCore

/// One directory on this Mac that holds a model's weights: a release the hub client
/// downloaded, or a variant packed here.
///
/// The unit is the directory, not the model, because they do not line up one to one. klein's
/// two variants pack from the one release, so deleting the release costs both their rebuilds
/// and deleting a variant costs only its own; the row has to say which.
public struct ModelStorageItem: Identifiable, Hashable, Sendable {
    /// How the directory came to be, which is also what getting it back would cost.
    public enum Kind: Hashable, Sendable {
        /// Fetched from the hub. Choosing a model that uses it again downloads it again.
        case download
        /// Packed on this Mac from a release, or by `make quantize` from one elsewhere.
        case built
    }

    /// The directory's path: two items never share one.
    public var id: String { url.path(percentEncoded: false) }
    /// What to call it: the model's own name when the directory is what loads, or the
    /// family's name and "release" when it is the source a variant is packed from.
    public let name: String
    public let kind: Kind
    /// The directory itself, the thing a size is measured over and a deletion removes.
    public let url: URL
    /// The catalog models that depend on this directory.
    public let modelIDs: [ModelDescriptor.ID]
    /// Whether what is there would load. False for a download that was stopped part-way,
    /// which is still worth listing: it takes space, and it resumes if the model is chosen.
    public let isComplete: Bool
    /// The directory's size, once `ModelStorage.measure` has walked it; nil before that.
    public var bytes: Int64?

    public init(
        name: String, kind: Kind, url: URL, modelIDs: [ModelDescriptor.ID], isComplete: Bool,
        bytes: Int64? = nil
    ) {
        self.name = name
        self.kind = kind
        self.url = url
        self.modelIDs = modelIDs
        self.isComplete = isComplete
        self.bytes = bytes
    }
}
