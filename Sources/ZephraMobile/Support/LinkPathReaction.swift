/// What a change of network path is worth doing about.
enum LinkPathReaction: Equatable {
    /// Nothing: the path is the one we were already on, or there is no path to dial over.
    case nothing
    /// Dial now rather than at the end of the wait.
    case redial
    /// Ask the Mac whether the session that looks live still is.
    case probe
}
