import AppKit
import UserNotifications

/// What clicking one of Zephra's notifications does: bring the app forward and put its window
/// in front.
///
/// Every notice Zephra posts is about something that happened in the one window — a picture
/// saved, a download finished, an update ready to install — so every one of them means the
/// same thing when it is clicked, and none of them needs to carry a destination. Without a
/// delegate the system brings the app forward and leaves the window wherever it was, which on
/// a Mac whose window had been closed with Command W is a Dock icon and nothing else.
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
        Task { @MainActor in
            NSApp.activate()
            // The one window, whatever the notice was about. `Window(id:)` keeps it in
            // `NSApp.windows`, and a window closed with Command W is reopened by the scene.
            NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }?.makeKeyAndOrderFront(nil)
        }
    }
}
