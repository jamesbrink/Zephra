import AppKit

extension Relaunch {
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
    @MainActor static func afterExit(of pid: pid_t, open bundle: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script(pid: pid, bundle: bundle)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try? process.run()
        NSApp.terminate(nil)
    }
}
