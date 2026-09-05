import AppKit

/// AppKit can defer Quit; SwiftUI's scene disappearance cannot wait for file/GPU work.
@MainActor
final class AppTermination: NSObject, NSApplicationDelegate {
    var shutdown: (@MainActor () async -> Void)?
    private var stopping = false

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
