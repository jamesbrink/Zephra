import AppKit
import SwiftUI

/// Zephra > Check for Updates…, where every Mac app keeps it: straight after About Zephra.
///
/// What the press comes to is reported through `ModalHost`, since a menu command is not a view
/// and has nowhere to hang a presentation binding. Three of the four answers are an alert;
/// "there is one" is not, because the banner in the window is already saying so and an alert
/// on top of it would be the same sentence twice. The app is brought forward instead, so the
/// banner is what the person is looking at.
struct UpdateCommands: Commands {
    let updates: UpdateChecker

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { check() }
                .disabled(updates.phase.isWorking)
        }
    }

    private func check() {
        Task {
            guard let outcome = await updates.checkNow(manual: true) else { return }
            if case .available = outcome {
                NSApp.activate()
                return
            }
            await ModalHost.report(
                outcome.message, outcome.detail,
                style: {
                    if case .upToDate = outcome { return .informational }
                    return .warning
                }())
        }
    }
}
