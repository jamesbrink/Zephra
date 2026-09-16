import AppKit
import UserNotifications

/// Delivers a `BackgroundNotice`, and only while Zephra is not the front app: a banner over
/// the window that made the picture would be saying what the window already shows.
///
/// Permission is asked for the first time there is something to say rather than at launch,
/// so the question arrives with its reason on the screen. The preference under Settings >
/// General switches the whole thing off, and switching it off asks nothing.
enum BackgroundNotices {
    /// The one request for permission this launch makes, kept as the task that is making it so
    /// two notices a moment apart wait on the same answer rather than each asking. Nothing
    /// reads what it answered: the system remembers the choice itself, and consulting a `false`
    /// cached here would mean a permission granted in System Settings afterwards did nothing
    /// until the next launch. So the banner is always handed over, and the system drops it when
    /// it may not be shown.
    private static var authorization: Task<Void, Never>?

    /// Posts `notice` if the app is in the background and the preference allows it.
    static func post(_ notice: BackgroundNotice) {
        guard AppSettings.flag(AppSettings.backgroundNotifications), !NSApp.isActive else { return }
        // The strings are read here, where the notice is, rather than inside the delivery:
        // what crosses into the notification centre's own types is plain text, the destination
        // included, which is why `NoticeDestination` spells itself as one.
        deliver(
            title: notice.title, body: notice.body,
            userInfo: notice.destination?.userInfo ?? [:])
    }

    /// Asks once, then hands the banner over. Both halves are the notification centre's own
    /// async calls, so each takes a freshly fetched centre and neither holds one across an
    /// await — the centre is not `Sendable`, and a captured one is a data race the compiler
    /// is right to refuse.
    private static func deliver(title: String, body: String, userInfo: [String: String]) {
        let ask = authorization ?? Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
        authorization = ask
        Task {
            await ask.value
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            // What a click on the banner is about, for `AppLifecycle+Notifications` to read
            // back. Empty for every notice that is about the window and nothing else.
            content.userInfo = userInfo
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
