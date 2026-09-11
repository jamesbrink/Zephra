/// Which shape of the link protocol this build speaks.
///
/// One number for the whole protocol rather than one per message: the two ends are a Mac app
/// and a phone app released separately, and the only question either can usefully answer at
/// the handshake is "do we agree about everything". A mismatch is `LinkErrorCode.protocolMismatch`
/// and the connection stops there, before any state crosses.
public enum LinkProtocolVersion {
    /// The version this build sends in its `Hello` and its `PairingPayload`.
    public static let current = 1
}
