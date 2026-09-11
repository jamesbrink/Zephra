import ZephraLinkProtocol

/// What one attempt at one road came to.
///
/// The middle case is the one that earns the type. A road that did not open says nothing about
/// the next road, so the next is tried; a Mac that answered and said no is the same Mac at the
/// end of every other road, so trying them would waste the person's time and lose the sentence
/// the Mac wrote for them.
enum LinkAttempt {
    /// The session is live.
    case connected
    /// The Mac answered and refused. Final, whatever roads are left.
    case refused(LinkError)
    /// The road did not open, or the Mac was not there.
    case unreachable(any Error)
}
