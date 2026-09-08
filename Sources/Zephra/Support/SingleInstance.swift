import AppKit

/// One Zephra at a time: a launch that finds another copy of the app already running brings
/// that one forward and exits before it has put up a window.
///
/// The system launches an app by its bundle identifier when a notification is clicked or a
/// document opened, and takes whichever copy LaunchServices has registered for the identifier,
/// which is not always the one running: a `make run` build beside a Debug build, a copy in
/// Applications beside one still in Downloads. Two Zephras with one library and one models
/// folder would write over each other, so the second stands down. The check is skipped under
/// a `ZEPHRA_PREVIEW_STATE`, since the frozen screenshot builds and the app-hosted tests run
/// beside a real one on purpose.
enum SingleInstance {
    /// Whether a launch should stand down: another process of the same app is running, and
    /// this one is not a frozen preview build. Pure, so it is tested; `yieldToRunningCopy`
    /// is the one place it is asked for real.
    static func shouldYield(runningPIDs: [pid_t], own: pid_t, previewState: String?) -> Bool {
        previewState == nil && runningPIDs.contains { $0 != own }
    }

    /// Hands this launch to the copy already running, if there is one, and exits.
    @MainActor static func yieldToRunningCopy() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let own = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        guard shouldYield(
            runningPIDs: running.map(\.processIdentifier), own: own, previewState: InterfacePreview.name)
        else { return }
        running.first { $0.processIdentifier != own }?.activate()
        exit(0)
    }
}
