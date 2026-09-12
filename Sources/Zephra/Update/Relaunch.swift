import Foundation

/// Opening the new Zephra once this one has gone.
///
/// The app cannot open itself: `SingleInstance.yieldToRunningCopy` brings the running copy
/// forward and exits, so a copy launched while this process is still alive would stand down
/// again and nothing would come back. So a two-line shell script is spawned that **waits for
/// this process id to go** and only then opens the bundle. It is deliberately not waited on,
/// its output goes nowhere, and it holds no reference to anything here: by the time it does
/// its work, there is nothing here to hold.
///
/// `/usr/bin/open -n` rather than the executable directly, so LaunchServices registers the new
/// copy, the Dock icon is the app's rather than a shell's, and the new process is not a child
/// of a process that is about to be reaped.
enum Relaunch {
    /// The script that waits for `pid` and opens `bundle`.
    ///
    /// Pure, so the quoting is a test rather than a thing found out by a path with a space in
    /// it on somebody's Mac. `kill -0` asks whether the process is there without signalling it,
    /// and its complaint is silenced because a dead process is the answer, not an error.
    static func script(pid: pid_t, bundle: URL) -> String {
        let path = quoted(bundle.standardizedFileURL.path(percentEncoded: false))
        return "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open -n \(path)"
    }

    /// One shell word, safe whatever is in it: single quotes take everything literally, and the
    /// one character they cannot carry, a single quote, is closed around.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
