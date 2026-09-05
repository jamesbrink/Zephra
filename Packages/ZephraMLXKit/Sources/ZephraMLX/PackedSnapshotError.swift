import Foundation

/// What a packed snapshot can be found to be before any weight of it is loaded.
///
/// Both kinds are refusals rather than fallbacks. A manifest that is present but unreadable
/// used to read as "unpacked", and the loader then failed a component later with a shape error
/// on a `.scales` tensor it had no place for; the snapshot's own path and the decoder's reason
/// are what a person needs to fix it. Shared by every family's manifest reader, and M8 of the
/// audit remediation merges those readers into one beside it.
public enum PackedSnapshotError: Error, LocalizedError, Equatable {
    /// `quantization.json` is there and cannot be decoded.
    case malformedManifest(URL, reason: String)
    /// The shards carry packed tensors and the snapshot has no manifest saying how finely.
    case packedWithoutManifest(firstKey: String)

    public var errorDescription: String? {
        switch self {
        case .malformedManifest(let url, let reason):
            """
            The quantization manifest at \(url.path(percentEncoded: false)) cannot be read: \
            \(reason). The build is not loadable as it stands; delete the directory and build \
            it again.
            """
        case .packedWithoutManifest(let firstKey):
            """
            The weights are packed (\(firstKey) is a quantization scale) but the snapshot has \
            no quantization.json saying how finely, so they cannot be loaded.
            """
        }
    }
}
