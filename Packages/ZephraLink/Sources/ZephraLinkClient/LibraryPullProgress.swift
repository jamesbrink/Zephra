/// How far a library pull has got, and what the Mac said its folder held when it last answered.
///
/// Two numbers, kept for one question: is the pull that is running still the right pull? A
/// resync sends the phone a fresh snapshot on the very session it was already reading the
/// library over, and restarting from nothing there threw away a few hundred entries and several
/// seconds of a link that may be a relay — for a folder that had not changed.
struct LibraryPullProgress: Equatable, Sendable {
    /// The offset the next page will be asked for at.
    var offset: Int
    /// How many entries the Mac said its folder held, as of the last page it answered.
    var total: Int
}
