import SwiftUI
import ZephraEngine

/// How the app looks, where images land, and what a run does with the seed.
struct GeneralSettings: View {
    @AppStorage(AppSettings.randomizeSeedEachRun) private var randomizeSeed = AppSettings.initialRandomizeSeedEachRun

    var body: some View {
        Form {
            Section("Appearance") {
                AppearanceControl()
            }
            Section("Images") {
                ImagesDirectoryRow()
                Toggle("Pick a new seed for every run", isOn: $randomizeSeed)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("General") {
    GeneralSettings()
        .frame(width: 480, height: 300)
        .environment(GenerationStore.preview(state: .ready))
        .environment(LibraryIndex(library: .pictures()))
}
