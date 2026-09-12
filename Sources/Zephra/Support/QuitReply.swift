import Foundation

/// What Quit should answer, as a pure function over the two things that can be in flight.
///
/// `AppLifecycle` already defers Quit while the store and the index settle their file work.
/// An update being put in place is the second such thing and the more serious one: between the
/// rename and the end of `ditto` there is no `Zephra.app` where there was one, and a Command Q
/// landing in that window would leave the Mac with only `Zephra.previous.app`. So the quit
/// waits for the swap to land and then takes the ordinary shutdown path.
///
/// Pure and separate from the delegate so every case is a test; `applicationShouldTerminate`
/// is the one place it is asked for real.
enum QuitReply: Equatable, Sendable {
    /// Nothing is in flight: quit now.
    case now
    /// An update is being put in place; wait for it, then shut down.
    case deferToInstall
    /// Let the store and the index finish their writes first.
    case deferToShutdown
    /// A quit is already being honoured; say so again and change nothing.
    case alreadyDeferred

    /// Whether this reply means the quit is deferred rather than taken at once.
    var isDeferred: Bool { self != .now }

    /// The answer for a Quit arriving right now.
    static func `for`(isInstalling: Bool, canShutDown: Bool, alreadyStopping: Bool) -> QuitReply {
        if alreadyStopping { return .alreadyDeferred }
        if isInstalling { return .deferToInstall }
        return canShutDown ? .deferToShutdown : .now
    }
}
