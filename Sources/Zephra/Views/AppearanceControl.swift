import SwiftUI

/// Whether the app follows the Mac's appearance, or is always light or always dark.
///
/// Only the picker: the choice is applied by `AppearanceApplier` on the main window, which
/// reads the same key, so the whole application changes as the segment moves.
struct AppearanceControl: View {
    @AppStorage(AppSettings.appearance) private var mode = AppSettings.initialAppearance

    var body: some View {
        Picker("Appearance", selection: $mode) {
            ForEach(AppearanceMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}

#Preview("Appearance") {
    Form { Section("Appearance") { AppearanceControl() } }
        .formStyle(.grouped)
        .frame(width: 480)
}
