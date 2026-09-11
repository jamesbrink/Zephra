/// Why a request or a connection was refused, as a word both ends agree on.
///
/// The reason string beside it is for a person; this is what code branches on.
public enum LinkErrorCode: String, Codable, Hashable, Sendable, CaseIterable {
    /// The device is not paired with this Mac and did not ask to pair.
    case notPaired
    /// The Mac declined: no pairing is open, or the user said no.
    case refused
    /// The Mac is doing something that cannot be interrupted.
    case busy
    /// The picture, model or blob named does not exist.
    case notFound
    /// The request did not make sense: a count out of bounds, a blob that was never started.
    case badRequest
    /// The Mac understood the request and does not implement it.
    case unsupported
    /// The device was paired and the pairing has since been withdrawn.
    case revoked
    /// The two ends do not speak the same `LinkProtocolVersion`.
    case protocolMismatch
}
