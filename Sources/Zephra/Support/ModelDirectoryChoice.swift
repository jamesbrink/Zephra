import AppKit
import ZephraCore
import ZephraEngine

/// Native folder and migration choices; the engine owns the operation after confirmation.
///
/// Both the panel and the questions after it are sheets on the window they were raised from,
/// which for the rows in Settings > Models is the Settings window (`ModalHost`). The three entry
/// points stay synchronous because their callers are buttons with nothing to wait for.
@MainActor
enum ModelDirectoryChoice {
    static func choose(store: GenerationStore, inventory: ModelInventory) {
        Task { await ask(store: store, inventory: inventory) }
    }

    static func confirm(_ folder: URL?, store: GenerationStore, inventory: ModelInventory) {
        Task { await ask(folder, store: store, inventory: inventory) }
    }

    static func move(from source: URL, store: GenerationStore, inventory: ModelInventory) {
        Task {
            guard await ModalHost.present(moveAlert(from: source, to: inventory.modelsDirectory))
                == .alertFirstButtonReturn
            else { return }
            apply(inventory.modelsDirectory, moving: source, store: store, inventory: inventory)
        }
    }

    private static func ask(store: GenerationStore, inventory: ModelInventory) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder Zephra keeps model weights in."
        panel.directoryURL = inventory.modelsDirectory
        guard await ModalHost.present(panel) == .OK, let chosen = panel.url else { return }
        await ask(chosen, store: store, inventory: inventory)
    }

    private static func ask(_ folder: URL?, store: GenerationStore, inventory: ModelInventory) async {
        let destination = folder ?? ModelLocations.default.root
        let source = inventory.modelsDirectory
        guard destination.resolvingSymlinksInPath() != source.resolvingSymlinksInPath() else { return }
        switch await ModalHost.present(alert(moving: source, to: destination)) {
        case .alertFirstButtonReturn: apply(folder, moving: nil, store: store, inventory: inventory)
        case .alertSecondButtonReturn: apply(folder, moving: source, store: store, inventory: inventory)
        default: break
        }
    }

    /// The question itself, apart from the asking, so what the keyboard does to it can be pinned
    /// without a window. Keep in Place is added first, so Return gives the answer that moves no
    /// gigabytes; Cancel is added last, where `NSAlert` finds it and gives it Escape.
    static func alert(moving source: URL, to destination: URL) -> NSAlert {
        ModalHost.warning(
            "Move existing models?",
            "New downloads and builds will use \(destination.path). Move existing model downloads and builds from \(source.path), or keep them where they are. Your image library stays where it is. Any model preparation in progress will stop; you can resume it from the canvas.",
            buttons: ["Keep in Place", "Move Models", "Cancel"]
        )
    }

    /// Move Models Here, which has no third answer that keeps the files where they are — so the
    /// only safe reply is Cancel, and `ModalHost.warning` takes Return off the move rather than
    /// leaving a multi-gigabyte migration under a stray keystroke. Guarded rather than
    /// destructive: it overwrites nothing, so it is not drawn in red.
    static func moveAlert(from source: URL, to destination: URL) -> NSAlert {
        ModalHost.warning(
            "Move models into the current folder?",
            "Move model downloads and builds from \(source.path) to \(destination.path). Existing destination models will not be overwritten. Model preparation will stop.",
            buttons: ["Move Models", "Cancel"],
            guarded: "Move Models"
        )
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
                if !warnings.isEmpty {
                    await ModalHost.report("Models moved with a warning", warnings.joined(separator: "\n\n"))
                }
            } catch {
                await inventory.refresh()
                await ModalHost.report("Models folder was not changed", error.localizedDescription)
            }
        }
    }
}
