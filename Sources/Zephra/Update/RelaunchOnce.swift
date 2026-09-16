/// The one relaunch a launch gets.
///
/// Two doors ask for the same relaunch after a lost GPU — the canvas's Relaunch Zephra button
/// and the five-second timer armed the instant the sentence went up — and the quit between them
/// is not instant: `AppLifecycle.applicationShouldTerminate` defers while the companion's
/// sessions drain, the store shuts down and the index saves, which with a paired phone attached
/// is seconds. A press at one second is therefore still quitting when the timer fires at five,
/// and the second ask spawns a second watcher script this process knows nothing about: both poll
/// the same process id, both `open -n` within 200 ms of each other, and
/// `SingleInstance.yieldToRunningCopy` can have each of the two copies stand down for the other
/// — a Mac left with no Zephra at all, which is the one outcome the whole feature exists to
/// prevent.
///
/// A value rather than a flag written into `Relaunch.afterExit`, so the rule is a test rather
/// than something only a terminating process could prove: `Relaunch` holds one of these on the
/// main actor and every door claims it before it spawns anything.
struct RelaunchOnce {
    private var claimed = false

    /// Takes the relaunch, or answers false because something already has it.
    mutating func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
