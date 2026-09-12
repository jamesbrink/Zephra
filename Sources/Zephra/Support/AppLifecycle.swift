import AppKit

/// The two moments SwiftUI's scenes cannot handle for the app: its launch, where a second copy
/// stands down for the one already running, and Quit, which AppKit can defer while the store
/// and the index settle their file and GPU work but a scene's disappearance cannot wait for.
///
/// An update being put in place is deferred the same way, and for a sharper reason: between
/// the running bundle being renamed aside and `ditto` finishing there is no `Zephra.app` where
/// there was one, and a Command Q landing in that window would leave the Mac with only
/// `Zephra.previous.app`. `isInstalling` is the composition root's answer to "is that
/// happening right now"; `QuitReply` is the whole decision.
@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    var shutdown: (@MainActor () async -> Void)?
    /// Whether an update is being swapped into place. Injected from `ZephraApp` rather than
    /// read from a type here, so this file names no updater.
    var isInstalling: (@MainActor () -> Bool)?
    private var stopping = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        SingleInstance.yieldToRunningCopy()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let reply = QuitReply.for(
            isInstalling: isInstalling?() ?? false,
            canShutDown: shutdown != nil,
            alreadyStopping: stopping)
        guard reply.isDeferred else { return .terminateNow }
        guard reply != .alreadyDeferred else { return .terminateLater }
        stopping = true
        Task {
            // The swap is a rename and a copy, seconds at most, and it is not cancellable:
            // stopping half way is the one outcome worse than waiting for it.
            while isInstalling?() == true {
                try? await Task.sleep(for: .milliseconds(200))
            }
            await shutdown?()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
