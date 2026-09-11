/// Why a sealed frame could not be sealed or opened.
///
/// Its own error rather than a `LinkError`, because none of these is something to tell a peer:
/// a channel that fails has already stopped trusting whatever is on the other end, and the only
/// honest answer is to close and say nothing.
///
/// Only `undecipherable` and `rekeyRequired` are the end of the channel. `replayed` and
/// `outOfWindow` are answers about one frame, which is dropped; `lost` is the session's own
/// decision, made by `OrderedInbox` when a gap goes unfilled.
public enum SecureChannelError: Error, Hashable, Sendable {
    /// The channel failed once already and will not be used again.
    case closed
    /// The bytes did not authenticate. The wrong key, a changed frame, a frame replayed as the
    /// other kind, or a counter somebody edited: the counter is the nonce, so changing it fails
    /// the tag. This is the one that closes the channel.
    case undecipherable
    /// A counter at or below the last one released downstream: a duplicate, or a frame that took
    /// so long that the stream moved past it. Dropped, never fatal.
    case replayed
    /// A counter a whole `SecureChannel.receiveWindow` past the release point. Too far ahead to
    /// be a reordering, so it is refused rather than held.
    case outOfWindow
    /// More frames held on one gap than `OrderedInbox.frameLimit` allows. An ordinary hole is
    /// stepped over and the owner told; this is the pathological case — hundreds of frames
    /// waiting on one that is never coming — and it ends the session.
    case lost
    /// Two to the thirty-two frames have gone one way. The nonce space is finished and the
    /// connection has to be made again.
    case rekeyRequired
}
