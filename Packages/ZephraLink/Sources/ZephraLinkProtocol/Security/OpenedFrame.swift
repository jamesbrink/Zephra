/// One frame off the channel: what it says, and where in the stream the sender put it.
///
/// The counter travels with the frame because the receiver is not finished with it — `OrderedInbox`
/// needs it to put the stream back in the order it was sealed in, and the channel needs to be told
/// which counters have been handed on. A tuple would do the same work with two unnamed halves; a
/// frame and its place in the stream are both worth naming.
public struct OpenedFrame: Hashable, Sendable {
    /// Where this frame sat in the sender's stream, counted from zero.
    public let counter: UInt64
    /// What arrived.
    public let frame: Frame

    /// One opened frame.
    public init(counter: UInt64, frame: Frame) {
        self.counter = counter
        self.frame = frame
    }
}
