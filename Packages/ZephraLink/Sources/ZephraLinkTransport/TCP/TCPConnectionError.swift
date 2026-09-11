/// Why a TCP road failed, where the failure is the road's own and not the peer's.
///
/// Its own error rather than a `LinkError`: none of these is something to tell a peer, because
/// in every one of them there is no longer a peer to tell.
public enum TCPConnectionError: Error, Hashable, Sendable {
    /// A frame was announced or offered larger than `TCPConnection.maxFrameBytes`.
    case frameTooLarge
    /// The connection did not become usable inside the time allowed.
    case timedOut
    /// The road was closed from this end.
    case closed
    /// The listener could not take a port.
    case notListening
}
