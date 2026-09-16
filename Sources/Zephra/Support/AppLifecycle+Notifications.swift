import AppKit
import UserNotifications

/// What clicking one of Zephra's notifications does: bring the app forward, put its window in
/// front, and then go wherever the notice said.
///
/// Most notices are about the one window — a download finished, an update ready to install —
/// so bringing it forward is all they mean. Without a delegate the system brings the app
/// forward and leaves the window wherever it was, which on a Mac whose window had been closed
/// with Command W is a Dock icon and nothing else.
///
/// The saved picture is the one notice about a thing rather than about the window, and it
/// carries its file name as a `NoticeDestination`. Where that goes is not decided here:
/// `onNoticeOpened` is the composition root's, so this file imports no library and no
/// workspace, and a notice whose destination this build cannot read is simply the window.
extension AppLifecycle: UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    /// The system calls this on its own queue, so the work hops to the main actor. The
    /// completion handler is called first and from here: it is not `Sendable`, so it may not
    /// cross into the task, and what it reports is that the response was received rather than
    /// that anything has finished being done about it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
        // Read here, off the notification's own content, so nothing that is not `Sendable`
        // crosses into the task: a destination is two strings.
        let destination = NoticeDestination(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in
            NSApp.activate()
            // The one window, whatever the notice was about. `Window(id:)` keeps it in
            // `NSApp.windows`, and a window closed with Command W is reopened by the scene.
            NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }?.makeKeyAndOrderFront(nil)
            // Only after the window is up: what this does is move the window somewhere, and
            // a window that is not yet in front has nowhere to move to.
            if let destination { self.onNoticeOpened?(destination) }
        }
    }
}
