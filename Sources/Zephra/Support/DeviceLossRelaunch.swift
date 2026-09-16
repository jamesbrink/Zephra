import Foundation

/// Whether a Mac that has just lost the GPU relaunches itself, and how long it waits first.
///
/// Relaunching is the only remedy there is, and most of the Macs this happens on have nobody
/// in front of them: one serving a paired phone, one being screen-shared, one left generating.
/// So the app does it on its own after a few seconds on screen — long enough that a person at
/// the keyboard reads the sentence and sees the window go rather than finding the app gone.
///
/// The guard is the other half. A GPU that is genuinely broken would fault again the moment the
/// new process touched it, and an app that relaunched every time would be a loop nobody could
/// get out of, taking whatever is in the prompt with it each time. So one automatic relaunch in
/// ten minutes: past that, the sentence and the button stand there and the person decides.
///
/// Pure, and the stamp comes in as an argument: `ZephraApp` reads it from `AppSettings` and
/// writes the new one, since a decision that read the disk could not be tested in microseconds.
enum DeviceLossRelaunch {
    /// How long the sentence stands on screen before the app relaunches itself.
    static let delay = Duration.seconds(5)
    /// How long one automatic relaunch suppresses the next.
    static let guardWindow: TimeInterval = 10 * 60

    /// What to do about a device loss noticed now.
    enum Answer: Hashable, Sendable {
        /// Relaunch on its own once the sentence has been up this long.
        case relaunchAfter(Duration)
        /// Say it and wait to be asked: one automatic relaunch has already happened recently.
        case offerButtonOnly
    }

    /// The answer for a Mac whose last automatic relaunch was `lastRelaunch` — nil when it has
    /// never made one — at `now`.
    ///
    /// A stamp in the future counts as recent. A clock that moved backwards is not a reason to
    /// start relaunching in a loop, and the button is still there.
    static func decide(lastRelaunch: Date?, now: Date) -> Answer {
        guard let lastRelaunch else { return .relaunchAfter(delay) }
        return now.timeIntervalSince(lastRelaunch) < guardWindow
            ? .offerButtonOnly
            : .relaunchAfter(delay)
    }
}
