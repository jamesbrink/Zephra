import AppKit
import UserNotifications

/// Delivers a `BackgroundNotice`, and only while Zephra is not the front app: a banner over
/// the window that made the picture would be saying what the window already shows.
///
/// Permission is asked for the first time there is something to say rather than at launch,
/// so the question arrives with its reason on the screen. The preference under Settings >
/// General switches the whole thing off, and switching it off asks nothing.
enum BackgroundNotices {
    /// Posts `notice` if the app is in the background and the preference allows it.
    static func post(_ notice: BackgroundNotice) {
        guard AppSettings.flag(AppSettings.backgroundNotifications), !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}
