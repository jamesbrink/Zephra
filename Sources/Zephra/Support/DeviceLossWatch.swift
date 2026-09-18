import Foundation
import Observation

/// Watches for the GPU going, for as long as the process lives rather than as long as a window
/// does.
///
/// The loss is one of the few engine facts the app acts on instead of refusing, and the acting —
/// `ZephraApp.relaunchAfterDeviceLoss` — is worth doing whether or not a window is open to
/// notice it. A view's `onChange` exists only while its view does, so a Mac left answering a
/// paired phone could lose its GPU behind a closed window and, if that window were never opened
/// again, have nothing left to catch the change: the crash it was waiting out would only be the
/// thing that ended the wait.
///
/// So the watcher is an object the composition root owns rather than a modifier on the scene, and
/// it holds no view state. The loss arrives as `lost` and is reported as `heard`, which is what
/// keeps this file from naming either the store or the relaunch, and what lets a test raise a
/// loss with no window in sight.
///
/// The loop is `CompanionHost`'s: `withObservationTracking` answers once and is re-armed, and its
/// callback runs before the write has landed, so the value is read on a later turn of the main
/// actor rather than inside the callback.
@MainActor
final class DeviceLossWatch {
    private let lost: @MainActor () -> Bool
    private let heard: @MainActor () -> Void
    /// Whether the loop is running, so the watch a reopened window asks for is the one already
    /// running rather than a second reader of the same fact.
    private var isWatching = false
    /// What `lost` answered when it was last read, so only a loss is heard and not every write:
    /// Observation reports a write of a value that did not move, and the store's own latch could
    /// settle on `true` more than once.
    private var lastRead = false

    init(lost: @escaping @MainActor () -> Bool, heard: @escaping @MainActor () -> Void) {
        self.lost = lost
        self.heard = heard
    }

    /// Starts watching, and reports a loss that has already happened.
    ///
    /// That first pass is the half a reopened window used to carry — here it does not depend on
    /// the window having been open at the moment of the loss. Idempotent, because the root calls
    /// it from the window's task and that task runs again on every reopen.
    func start() {
        guard !isWatching else { return }
        isWatching = true
        lastRead = lost()
        if lastRead { heard() }
        watch()
    }

    /// Waits for the next change to whatever `lost` reads, then asks again once the main actor
    /// comes round and the write has landed, and waits again.
    ///
    /// The turn it takes is unstructured, so a window closing cancels nothing; the watch is torn
    /// down with the app.
    private func watch() {
        withObservationTracking {
            _ = lost()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isLost = self.lost()
                let wasLost = self.lastRead
                self.lastRead = isLost
                if isLost, !wasLost { self.heard() }
                self.watch()
            }
        }
    }
}
