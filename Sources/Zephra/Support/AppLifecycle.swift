import AppKit

/// The two moments SwiftUI's scenes cannot handle for the app: its launch, where a second copy
/// stands down for the one already running, and Quit, which AppKit can defer while the store
/// and the index settle their file and GPU work but a scene's disappearance cannot wait for.
@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    var shutdown: (@MainActor () async -> Void)?
    private var stopping = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        SingleInstance.yieldToRunningCopy()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let shutdown else { return .terminateNow }
        guard !stopping else { return .terminateLater }
        stopping = true
        Task {
            await shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
