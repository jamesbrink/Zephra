import AppKit
import SwiftUI
import ZephraCore
import ZephraEngine

/// The folder Zephra keeps model weights in, and the way to change it.
///
/// Choosing a folder changes where the next download and the next build go, and nothing else:
/// what is already on disk stays where it is and keeps working. So the folder can be moved to
/// an external disk without a sixty-gigabyte copy, and moving it back costs nothing either.
///
/// The app is not sandboxed, so the choice is stored as a plain path and no bookmark is needed.
struct ModelsDirectoryRow: View {
    @Environment(GenerationStore.self) private var store
    @Environment(ModelInventory.self) private var inventory
    @AppStorage(AppSettings.modelsDirectory) private var path = ""

    var body: some View {
        DirectoryRow("Models are kept in", inventory.modelsDirectory) {
            Button("Change…") { choose() }
            if !path.isEmpty {
                Button("Use Default") { apply(nil) }
            }
        }
    }

    /// Asks for a folder, directories only, starting where the models are now.
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder Zephra keeps model weights in."
        panel.directoryURL = inventory.modelsDirectory
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        apply(chosen)
    }

    /// Stores the choice and hands it to the engine and the list. A nil folder is the default
    /// one, which is stored as an empty path so that a later change of default is picked up.
    private func apply(_ folder: URL?) {
        path = folder?.path(percentEncoded: false) ?? ""
        let locations = folder.map { ModelLocations(root: $0) } ?? .default
        store.setModelLocations(locations)
        inventory.setLocations(locations)
        Task {
            await inventory.refresh()
            await store.refreshAvailability()
        }
    }
}
