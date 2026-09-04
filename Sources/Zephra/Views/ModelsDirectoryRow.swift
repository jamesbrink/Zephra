import SwiftUI
import ZephraCore
import ZephraEngine

/// The selected models folder and explicit choices for keeping or moving existing files.
struct ModelsDirectoryRow: View {
    @Environment(GenerationStore.self) private var store
    @Environment(ModelInventory.self) private var inventory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DirectoryRow("Models are kept in", inventory.modelsDirectory) {
                Button("Change…") { ModelDirectoryChoice.choose(store: store, inventory: inventory) }
                    .disabled(!store.canChangeModelDirectory)
                if inventory.modelsDirectory.standardizedFileURL != ModelLocations.default.root.standardizedFileURL {
                    Button("Use Default") {
                        ModelDirectoryChoice.confirm(nil, store: store, inventory: inventory)
                    }
                    .disabled(!store.canChangeModelDirectory)
                }
            }
            if !store.modelLocations.previous.isEmpty {
                Menu("Move Models Here…") {
                    ForEach(store.modelLocations.previous, id: \.self) { source in
                        Button(source.path(percentEncoded: false)) {
                            ModelDirectoryChoice.move(from: source, store: store, inventory: inventory)
                        }
                    }
                }
                .disabled(!store.canChangeModelDirectory)
                .help("Move models from a previously selected folder into this folder.")
            }
            if let progress = store.modelDirectoryProgress {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.caption)
                }
            } else if !store.canChangeModelDirectory {
                Text("Finish generation and queued work before changing this folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
