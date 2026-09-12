import SwiftUI
import ZephraEngine

/// How the app looks, where images land, what a run does with the seed, whether the Mac says
/// when a run, a download or an update is ready behind another app, and whether Zephra looks
/// for a newer build of itself.
///
/// The appearance section has no heading: the picker is already labelled "Appearance", and
/// a heading saying it again read as a stutter. The seed toggle is a fact about a run, not
/// about the images folder, so it has a section of its own, with how a seed is written under
/// it, and the notification toggle sits with them because a run is what it announces. Updates
/// are their own section: what they are about is the app rather than anything it makes.
struct GeneralSettings: View {
    @AppStorage(AppSettings.randomizeSeedEachRun) private var randomizeSeed = AppSettings.initialRandomizeSeedEachRun
    @AppStorage(AppSettings.backgroundNotifications) private var notify = AppSettings.initialBackgroundNotifications
    @AppStorage(AppSettings.checksForUpdates) private var checksForUpdates = AppSettings.initialChecksForUpdates

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
                Toggle("Notify when an image, a download or an update is ready in the background", isOn: $notify)
            }
            Section("Updates") {
                Toggle("Check for new versions of Zephra automatically", isOn: $checksForUpdates)
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
