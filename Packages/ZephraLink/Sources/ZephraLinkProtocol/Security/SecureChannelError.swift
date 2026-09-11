/// Why a sealed frame could not be sealed or opened.
///
/// Its own error rather than a `LinkError`, because none of these is something to tell a peer:
/// a channel that fails has already stopped trusting whatever is on the other end, and the only
/// honest answer is to close and say nothing.
public enum SecureChannelError: Error, Hashable, Sendable {
    /// The channel failed once already and will not be used again.
    case closed
    /// The bytes did not authenticate. The wrong key, a changed frame, a frame replayed as the
    /// other kind, or one lost or reordered: the counter is implicit, so a gap in the stream
    /// decrypts under the wrong nonce and arrives here too.
    case undecipherable
    /// Two to the thirty-two frames have gone one way. The nonce space is finished and the
    /// connection has to be made again.
    case rekeyRequired
}
