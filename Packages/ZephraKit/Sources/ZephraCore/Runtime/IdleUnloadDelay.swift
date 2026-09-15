/// How long a loaded model may sit doing nothing before its weights are given back.
///
/// Off by default: weights that went away while somebody was reading are weights that have to be
/// read again, and a Mac with the room to hold them has no reason to. It is the Mac that is
/// short of memory, or shared with something else, that wants the clock.
public enum IdleUnloadDelay: Int, Codable, Hashable, Sendable, CaseIterable {
    case never = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    /// The wait, or nil when the weights stay until something else moves them.
    public var duration: Duration? { self == .never ? nil : .seconds(rawValue * 60) }
}
