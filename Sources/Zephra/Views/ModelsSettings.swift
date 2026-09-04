import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraSnapshot

/// Where the models live on this Mac, what each occupies, and a way to send one to the Trash.
///
/// The list is the disk's, read afresh each time the tab opens and after every deletion, so a
/// model fetched by `make prefetch` or removed in the Finder shows up as it is. A directory the
/// loaded model is using cannot be deleted from under it: its row says so, and choosing another
/// model first frees it.
struct ModelsSettings: View {
    @Environment(GenerationStore.self) private var store
    @Environment(ModelInventory.self) private var inventory
    @State private var pendingDeletion: ModelStorageItem?

    var body: some View {
        Form {
            Section("Kept in") {
                DirectoryRow("Downloads", inventory.downloadsDirectory)
                DirectoryRow("Built variants", inventory.builtDirectory)
            }
            Section {
                if inventory.items.isEmpty {
                    Text("Nothing downloaded or built yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(inventory.items) { item in
                    ModelStorageRow(item: item, inUse: isInUse(item)) { pendingDeletion = item }
                }
            } header: {
                Text("On this Mac")
            } footer: {
                ModelStorageTotal()
            }
            if let failure = inventory.lastFailure {
                Section { NoticeCapsule(failure) }
            }
        }
        .formStyle(.grouped)
        .task { await inventory.refresh() }
        .confirmationDialog(
            "Move to the Trash?", isPresented: isConfirming, presenting: pendingDeletion
        ) { item in
            Button("Move to Trash", role: .destructive) { delete(item) }
        } message: { item in
            Text(consequence(of: item))
        }
    }

    /// Whether the engine is holding, or about to hold, weights from this directory.
    private func isInUse(_ item: ModelStorageItem) -> Bool {
        if let loaded = store.loadedDescriptor, item.modelIDs.contains(loaded.id) { return true }
        return store.state.isBusy && item.modelIDs.contains(store.descriptor.id)
    }

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    /// What deleting this directory costs, so the dialog says it before the click.
    private func consequence(of item: ModelStorageItem) -> String {
        let size = item.bytes.map { $0.formatted(.byteCount(style: .file)) } ?? "its"
        let cost = switch item.kind {
        case .download: "downloads it again"
        case .built: "builds it again"
        }
        return "\(item.name) frees \(size). It can be put back from the Finder; choosing a model "
            + "that needs it \(cost)."
    }

    private func delete(_ item: ModelStorageItem) {
        Task {
            await inventory.delete(item)
            await store.refreshAvailability()
        }
    }
}

#Preview("Models") {
    ModelsSettings()
        .frame(width: 480, height: 480)
        .environment(GenerationStore.preview(state: .ready))
        .environment(ModelInventory())
}
