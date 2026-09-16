import AppKit
import os

extension Relaunch {
    /// This launch's one relaunch, claimed by whichever door asks first. See `RelaunchOnce`.
    @MainActor static var once = RelaunchOnce()

    /// Relaunches the copy that is running, which is what a lost GPU asks for: the same script
    /// and the same run-loop quit the updater uses, over this bundle rather than a new one.
    @MainActor static func thisApp() {
        // A fresh start *is* its environment: its own preferences suite, its own models folder
        // and its own image library all come from `ZEPHRA_FRESH_START`, and `open -n` carries no
        // environment at all. The copy that came back would be an ordinary Zephra over the
        // person's real library and real models, which is the one thing a fresh start promises
        // it will not touch. `make run-fresh` is how one is started and how it comes back.
        if let fresh = FreshStart.current {
            log.error(
                """
                not relaunching: this is a fresh start under \
                \(fresh.root.path(percentEncoded: false), privacy: .public) \
                — start it again with make run-fresh
                """)
            return
        }
        afterExit(of: ProcessInfo.processInfo.processIdentifier, open: Bundle.main.bundleURL)
    }

    /// Spawns the waiting script and quits through the ordinary path.
    ///
    /// `NSApp.terminate(nil)`, never `exit()`: `AppLifecycle.applicationShouldTerminate` defers
    /// the quit while `GenerationStore.shutdown`, `LibraryIndex.shutdown` and the Metal
    /// synchronize settle, and a call to `exit` here would be the one way out of the app that
    /// skips all three, losing a save that had not landed.
    ///
    /// The script is never waited on and its output goes nowhere. It outlives this process on
    /// purpose, which is the whole point of it, and it is the shell's child rather than a
    /// process this one has to reap.
    ///
    /// One per launch, whichever door asked: a second script would poll the same process id and
    /// open a second copy beside the first (`RelaunchOnce`). The second `terminate` would be
    /// harmless — `QuitReply` answers `.alreadyDeferred` — but the second script is not.
    @MainActor static func afterExit(of pid: pid_t, open bundle: URL) {
        guard once.claim() else {
            log.error("a relaunch is already under way; this one opens nothing")
            return
        }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script(pid: pid, bundle: bundle)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try? process.run()
        // Handed to the run loop rather than called here. `terminate(_:)` answers a deferred
        // reply by spinning a nested event loop *inside the call*, and the shutdown that
        // produces the reply is a main-actor task: called from a main-actor job, that loop sat
        // on the one executor the reply needed, and the app never quit. From a run-loop
        // perform the call comes the way a menu's Quit does, with the main actor free.
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }

    private static let log = Logger(subsystem: "io.zephra", category: "update")
}
