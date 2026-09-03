import AppKit
import SwiftUI
import ZephraEngine

/// How the app looks, where images land, and what a run does with the seed.
struct GeneralSettings: View {
    @Environment(GenerationStore.self) private var store
    @AppStorage(AppSettings.randomizeSeedEachRun) private var randomizeSeed = AppSettings.initialRandomizeSeedEachRun

    var body: some View {
        Form {
            Section("Appearance") {
                AppearanceControl()
            }
            Section("Images") {
                LabeledContent("Images are saved to") {
                    HStack {
                        Text(store.outputDirectory.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Open") {
                            NSWorkspace.shared.open(store.outputDirectory)
                        }
                    }
                }
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
}
