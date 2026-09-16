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
    /// What a clicked notification that named somewhere is worth doing about it, once the app
    /// is forward and the window is up. Injected from the composition root the way
    /// `isInstalling` is, so this file names neither the library nor the workspace: all it
    /// knows is that a notice carried a destination.
    ///
    /// Setting it delivers whatever arrived before it was there, because the case the whole
    /// destination is for — a banner left in Notification Center overnight and clicked with
    /// Zephra not running — arrives in the other order: the delegate is set in
    /// `applicationDidFinishLaunching` and the system calls back at once, while this closure is
    /// assigned from the root view's `.task`, which has not run yet.
    var onNoticeOpened: (@MainActor (NoticeDestination) -> Void)? {
        didSet {
            guard let onNoticeOpened, let pending = pendingNotice else { return }
            pendingNotice = nil
            onNoticeOpened(pending)
        }
    }

    /// Where a click that landed before anything could answer it was going. One at most: two
    /// notifications cannot be clicked before the first frame, and the newer ask is the one a
    /// person would mean anyway.
    private var pendingNotice: NoticeDestination?
    private var stopping = false

    /// Hands a clicked notification's destination to whoever answers them, or holds it until
    /// somebody does.
    func deliver(_ destination: NoticeDestination) {
        guard let onNoticeOpened else {
            pendingNotice = destination
            return
        }
        onNoticeOpened(destination)
    }

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
