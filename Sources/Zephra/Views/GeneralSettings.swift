import SwiftUI
import ZephraEngine

/// How the app looks, where images land, and what a run does with the seed.
///
/// The appearance section has no heading: the picker is already labelled "Appearance", and
/// a heading saying it again read as a stutter. The seed toggle is a fact about a run, not
/// about the images folder, so it has a section of its own.
struct GeneralSettings: View {
    @AppStorage(AppSettings.randomizeSeedEachRun) private var randomizeSeed = AppSettings.initialRandomizeSeedEachRun

    var body: some View {
        Form {
            Section {
                AppearanceControl()
            }
            Section("Images") {
                ImagesDirectoryRow()
            }
            Section("Generation") {
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
