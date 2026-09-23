import SwiftUI

/// Settings > General's Updates section: the switch, and when the last check ran.
///
/// A section of its own because it reads the `UpdateChecker` beside the preference, and
/// `GeneralSettings` is already at three stored properties.
///
/// Switching the preference on starts the checking straight away. The loop re-reads the
/// preference at every tick, so switching it off needs nothing; switching it back on used to
/// need a relaunch, since nothing asked the checker to begin again.
struct UpdateCheckSettings: View {
    @AppStorage(AppSettings.checksForUpdates) private var checksForUpdates = AppSettings.initialChecksForUpdates
    @Environment(UpdateChecker.self) private var updates: UpdateChecker?

    var body: some View {
        Section("Updates") {
            Toggle("Check for new versions of Zephra automatically", isOn: $checksForUpdates)
                .onChange(of: checksForUpdates) { _, on in
                    if on { updates?.startChecking() }
                }
            caption
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A relative `Text`, which SwiftUI keeps ticking; the checker is observed, so a check that
    /// finishes while the tab is up redraws the line.
    private var caption: Text {
        guard let note = updates?.lastCheck else { return Text(UpdateCheckNote.notChecked) }
        return Text("Last checked ") + Text(note.date, style: .relative) + Text(" ago\(note.tail)")
    }
}
