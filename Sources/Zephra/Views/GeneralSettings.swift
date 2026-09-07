import SwiftUI
import ZephraEngine

/// How the app looks, where images land, what a run does with the seed, and whether the Mac
/// says when a run or a download ends behind another app.
///
/// The appearance section has no heading: the picker is already labelled "Appearance", and
/// a heading saying it again read as a stutter. The seed toggle is a fact about a run, not
/// about the images folder, so it has a section of its own, with how a seed is written under
/// it, and the notification toggle sits with them because a run is what it announces.
struct GeneralSettings: View {
    @AppStorage(AppSettings.randomizeSeedEachRun) private var randomizeSeed = AppSettings.initialRandomizeSeedEachRun
    @AppStorage(AppSettings.backgroundNotifications) private var notify = AppSettings.initialBackgroundNotifications

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
                SeedFormatControl()
                Toggle("Notify when an image or a download finishes in the background", isOn: $notify)
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
