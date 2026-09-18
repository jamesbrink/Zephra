import AppKit
import Testing

@testable import Zephra

/// The one fact a Quit leaves behind that outlives its own reply: `stopping`, which the
/// device-loss relaunch reads before its watcher script may spawn. A person who answers a
/// lost GPU with ⌘Q must get a closed app, not one that opens itself again a few seconds
/// later — and `RelaunchOnce` is per launch, so a relaunch spent on the reopening the person
/// refused is also a relaunch not available to the next loss.
///
/// Only the immediate reply is driven here on purpose: the deferred path ends in
/// `reply(toApplicationShouldTerminate:)` on a live `NSApplication`, which a hosted test has
/// no business triggering. That path's decision is `QuitReplyTests`; what is new and worth a
/// test is that even the *immediate* reply records the ask.
@MainActor
@Suite("A Quit is stopping, whatever its reply")
struct AppLifecycleStoppingTests {
    @Test("a Quit that nothing defers still marks the app as stopping")
    func anImmediateQuitIsStopping() {
        let lifecycle = AppLifecycle()
        #expect(!lifecycle.stopping)
        let reply = lifecycle.applicationShouldTerminate(NSApplication.shared)
        #expect(reply == .terminateNow, "with no shutdown injected there is nothing to defer to")
        #expect(lifecycle.stopping, "and the ask is still recorded")
    }

    @Test("asking again while stopping defers without starting new work")
    func aSecondAskIsAlreadyDeferred() {
        let lifecycle = AppLifecycle()
        #expect(lifecycle.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(
            lifecycle.applicationShouldTerminate(NSApplication.shared) == .terminateLater,
            "the second ask joins the first; it starts no shutdown of its own")
        #expect(lifecycle.stopping)
    }
}
