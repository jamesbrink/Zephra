import SwiftUI

/// Opens Settings. A `SettingsLink` rather than a button that sends an action, so the window
/// comes forward if it is already open instead of a second one appearing.
struct SettingsButton: View {
    var body: some View {
        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }
        .help("Settings")
    }
}

#Preview("Settings") {
    SettingsButton()
        .padding()
}
