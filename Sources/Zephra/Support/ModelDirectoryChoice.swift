import AppKit
import ZephraCore
import ZephraEngine

/// Native folder and migration choices; the engine owns the operation after confirmation.
@MainActor
enum ModelDirectoryChoice {
    static func choose(store: GenerationStore, inventory: ModelInventory) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder Zephra keeps model weights in."
        panel.directoryURL = inventory.modelsDirectory
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        confirm(chosen, store: store, inventory: inventory)
    }

    static func confirm(_ folder: URL?, store: GenerationStore, inventory: ModelInventory) {
        let destination = folder ?? ModelLocations.default.root
        let source = inventory.modelsDirectory
        guard destination.resolvingSymlinksInPath() != source.resolvingSymlinksInPath() else { return }
        let alert = NSAlert()
        alert.messageText = "Move existing models?"
        alert.informativeText = "New downloads and builds will use \(destination.path). Move existing model downloads and builds from \(source.path), or keep them where they are. Your image library stays where it is. Any model preparation in progress will stop; you can resume it from the canvas."
        alert.addButton(withTitle: "Move Models")
        alert.addButton(withTitle: "Keep in Place")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            apply(folder, moving: source, store: store, inventory: inventory)
        case .alertSecondButtonReturn:
            apply(folder, moving: nil, store: store, inventory: inventory)
        default: break
        }
    }

    static func move(from source: URL, store: GenerationStore, inventory: ModelInventory) {
        let alert = NSAlert()
        alert.messageText = "Move models into the current folder?"
        alert.informativeText = "Move model downloads and builds from \(source.path) to \(inventory.modelsDirectory.path). Existing destination models will not be overwritten. Model preparation will stop."
        alert.addButton(withTitle: "Move Models")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        apply(inventory.modelsDirectory, moving: source, store: store, inventory: inventory)
    }

    private static func apply(
        _ folder: URL?, moving source: URL?, store: GenerationStore, inventory: ModelInventory
    ) {
        let old = inventory.modelsDirectory
        let locations = AppSettings.proposedModelLocations(folder, leaving: old)
        Task {
            do {
                let warnings = try await store.changeModelDirectory(to: locations, moving: source)
                AppSettings.recordModelsDirectory(folder, leaving: old)
                inventory.setLocations(locations)
                await inventory.refresh()
                await store.refreshAvailability()
                if !warnings.isEmpty { report("Models moved with a warning", warnings.joined(separator: "\n\n")) }
            } catch {
                await inventory.refresh()
                report("Models folder was not changed", error.localizedDescription)
            }
        }
    }

    private static func report(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
