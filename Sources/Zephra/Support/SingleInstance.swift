import AppKit
import ZephraEngine

/// One Zephra at a time: a launch that finds another copy of the app already running brings
/// that one forward and exits before it has put up a window.
///
/// The system launches an app by its bundle identifier when a notification is clicked or a
/// document opened, and takes whichever copy LaunchServices has registered for the identifier,
/// which is not always the one running: a `make run` build beside a Debug build, a copy in
/// Applications beside one still in Downloads. Two Zephras with one library and one models
/// folder would write over each other, so the second stands down. A launch that owns neither
/// is exempt: the frozen `ZEPHRA_PREVIEW_STATE` screenshot builds and the app-hosted tests run
/// beside a real one on purpose, and a `ZEPHRA_FRESH_START` launch has a models folder, a
/// library and a preferences domain of its own, which is the whole point of it.
enum SingleInstance {
    /// Whether a launch should stand down: another process of the same app is running, and
    /// this one shares its library and models folder. Pure, so it is tested;
    /// `yieldToRunningCopy` is the one place it is asked for real.
    static func shouldYield(runningPIDs: [pid_t], own: pid_t, isolated: Bool) -> Bool {
        !isolated && runningPIDs.contains { $0 != own }
    }

    /// Whether this launch owns its own library and models folder rather than sharing the real
    /// one: a frozen `ZEPHRA_PREVIEW_STATE` build, or a `ZEPHRA_FRESH_START` launch. Pure, so
    /// it is tested on its own; `yieldToRunningCopy` is the one place it is asked for real.
    ///
    /// This takes `InterfacePreview.requestedState`, not `InterfacePreview.name`. `name` is the
    /// raw `ZEPHRA_PREVIEW_STATE` environment variable, read in every build configuration;
    /// `requestedState` is `#if DEBUG` and answers nil in Release however the variable is set.
    /// Testing `name` stands the guard down in a shipped Release for any value of the variable
    /// at all — the frozen preview it names is inert there, so what actually launches is an
    /// ordinary second Zephra, wrongly believing itself isolated, over the same library and
    /// models folder as the copy it should have yielded to.
    static func isolated(previewState: EngineState?, freshStart: FreshStart?) -> Bool {
        previewState != nil || freshStart != nil
    }

    /// Hands this launch to the copy already running, if there is one, and exits.
    @MainActor static func yieldToRunningCopy() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let own = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        let isolatedLaunch = isolated(previewState: InterfacePreview.requestedState, freshStart: FreshStart.current)
        guard shouldYield(runningPIDs: running.map(\.processIdentifier), own: own, isolated: isolatedLaunch)
        else { return }
        running.first { $0.processIdentifier != own }?.activate()
        exit(0)
    }
}
