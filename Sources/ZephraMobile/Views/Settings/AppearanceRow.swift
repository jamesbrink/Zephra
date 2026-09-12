import SwiftUI
import ZephraStyle

/// Whether the phone follows the system's appearance, or is always light or always dark.
///
/// Only the picker: the choice is applied by `AppearancePreference` at the root, which reads
/// the same key, so the whole app changes as the segment moves.
struct AppearanceRow: View {
    @AppStorage(MobileSettings.appearance) private var mode = MobileSettings.initialAppearance

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
    Form { AppearanceRow() }
}
