import Foundation
import os

/// The composition root's answer to a lost GPU: relaunch, on its own, once.
///
/// Where the rest of the app only refuses work, this is the part that acts, so it belongs here
/// beside the other things the root does to the whole app — the library wiring, the link, the
/// updater. The decision is `DeviceLossRelaunch`'s and the quit is `Relaunch`'s, the one the
/// updater goes through; nothing new is written about either.
extension ZephraApp {
    /// Starts the app-lifetime watch on the GPU, from the window's task.
    ///
    /// The window is where the composition root's state is wired, but it is not what keeps the
    /// watch alive: the watch is a plain object held here for the length of the launch, and its
    /// own loop runs on the main actor independently of any scene. Calling it again on a window
    /// reopened is answered by `DeviceLossWatch.start` doing nothing, so the one reader of the
    /// store's latch stays the one reader.
    ///
    /// Not under a frozen screenshot build, which is the same guard the relaunch carries — and
    /// the hosted tests run inside one, so what is tested is the watch itself, not a preview's
    /// refusal of it.
    @MainActor
    func startDeviceLossWatch() {
        guard InterfacePreview.requestedState == nil else { return }
        let store = store
        let watch = lossWatch ?? DeviceLossWatch(
            lost: { store.deviceLost },
            heard: relaunchAfterDeviceLoss)
        lossWatch = watch
        watch.start()
    }

    /// Relaunches this copy a few seconds after the sentence went up, unless an automatic
    /// relaunch has already happened inside the guard window, when the canvas's Relaunch
    /// Zephra button is the whole of the offer.
    ///
    /// The stamp is written when the relaunch is *decided* rather than when it happens: the
    /// process that would write it afterwards is the process that is going away.
    @MainActor
    func relaunchAfterDeviceLoss() {
        // A frozen screenshot build quits itself for nothing, and the hosted tests run in one.
        // The rule `UpdateChecker.start()` and `startCompanion` both follow.
        guard InterfacePreview.requestedState == nil else { return }
        // A Quit already asked for is the person's own answer to the lost GPU, so it is taken
        // at face value before anything is spent arming against it.
        guard !termination.stopping else { return }
        let log = Logger(subsystem: "io.zephra", category: "engine")
        let answer = DeviceLossRelaunch.decide(
            lastRelaunch: AppSettings.deviceLossRelaunchStamp(), now: Date())
        guard case .relaunchAfter(let wait) = answer else {
            log.error("the GPU is lost and Zephra relaunched itself recently; offering the button only")
            return
        }
        AppSettings.recordDeviceLossRelaunch(Date())
        log.error("the GPU is lost; relaunching Zephra in \(wait.components.seconds) seconds")
        Task { @MainActor in
            try? await Task.sleep(for: wait)
            // The wait is also the person's to answer with ⌘Q, and the sentence standing on
            // screen is an offer they may decline that way. Spawning the watcher script after
            // that would reopen the app they just closed, and spend the launch's one
            // `RelaunchOnce` doing it; the guard window's stamp is already burned, which only
            // costs the next loss its automatic relaunch — a person who just quit by hand is
            // the one person who will not mind starting it by hand again.
            guard !termination.stopping else {
                log.error("Zephra was quit while the device-loss relaunch waited; not reopening it")
                return
            }
            Relaunch.thisApp()
        }
    }
}
