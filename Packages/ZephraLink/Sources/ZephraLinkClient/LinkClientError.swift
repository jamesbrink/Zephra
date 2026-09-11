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
    /// The Mac did not answer inside the time allowed.
    case timedOut
    /// A message arrived where another was expected, which means the two ends disagree.
    case unexpectedMessage(kind: String)
    /// The reply was not the shape the command asks for.
    case unexpectedReply
    /// Too many blobs were part way through at once, and this was the oldest.
    case tooManyTransfers
}
