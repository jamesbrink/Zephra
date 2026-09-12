/// Why the phone's own side could not do what was asked.
///
/// Apart from `LinkError`, which is the Mac's refusal and carries words written for a person to
/// read. These are this end's: there was no session, or the Mac never answered.
public enum LinkClientError: Error, Hashable, Sendable {
    /// There is no live session to send over.
    case notConnected
    /// No Mac has been paired with yet.
    case notPaired
    /// No road to the Mac worked.
    case unreachable
    /// The relay would not let this phone into the Mac's room.
    ///
    /// Apart from the Mac's own `notPaired`, which is an answer this phone's key was weighed
    /// against: this one is the relay reading a list the Mac wrote, and a Mac that has just
    /// restarted, or that joined its room a moment before it knew its own pairings, is on the
    /// far side of a list that will be right again shortly. So it reads as "not yet", never as
    /// "you have been forgotten".
    case notAdmitted
    /// The Mac did not answer inside the time allowed.
    case timedOut
    /// A message arrived where another was expected, which means the two ends disagree.
    case unexpectedMessage(kind: String)
    /// The reply was not the shape the command asks for.
    case unexpectedReply
    /// Too many blobs were part way through at once, and this was the oldest.
    case tooManyTransfers
    /// A hole in the stream swallowed whatever was going to answer this: the reply to a request,
    /// or a chunk of a transfer. Nothing is wrong with the link, so the caller asks again.
    case lost
}

extension LinkClientError {
    /// Whether asking again is worth anything. Both of these are about one message and not about
    /// the link: a reply that never came and a transfer a gap swallowed are the two ways a frame
    /// goes missing, and one more attempt is what the far end expects — every `Command` is safe
    /// to repeat, and the two that would otherwise count are answered from what they already did.
    public var isWorthRepeating: Bool {
        self == .timedOut || self == .lost
    }
}
