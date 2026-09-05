import SwiftUI
import ZephraEngine

/// Downloads have their own rows even while another model is generating.
struct ModelDownloadsSection: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        if !store.downloads.items.isEmpty {
            Section("Downloads") {
                ForEach(store.downloads.items) { row in ModelDownloadRow(download: row) }
            }
        }
    }
}
