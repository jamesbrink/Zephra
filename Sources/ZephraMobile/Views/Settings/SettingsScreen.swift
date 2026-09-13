import SwiftUI

/// The Mac this phone is paired to, how it is being reached, and what can be done about it.
///
/// A `Form` rather than a screen of our own drawing: this is the one surface in the app that is
/// about the phone rather than about the pictures, and it should look like every other settings
/// screen on the device. Each row is its own view, so what a row says is changed in one file.
struct SettingsScreen: View {
    var body: some View {
        NavigationStack {
            Form {
                HostsSection()
                Section("Appearance") { AppearanceRow() }
                Section("Generation") {
                    RandomizeSeedRow()
                    SeedFormatRow()
                }
                Section("Storage") { CacheRow() }
                Section("About") { AboutRow() }
            }
            .navigationTitle(MobileTab.settings.title)
        }
    }
}

#Preview("Settings") {
    SettingsScreen()
        .environment(MobilePreview.client() ?? MobilePreview.unpairedClient())
}
