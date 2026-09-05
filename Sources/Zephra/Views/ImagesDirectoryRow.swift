import SwiftUI
import ZephraEngine

/// The image library uses the same explicit folder and migration choices as Models.
struct ImagesDirectoryRow: View {
    @Environment(GenerationStore.self) private var store
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DirectoryRow("Images are saved to", store.outputDirectory) {
                Button("Change…") { ImageDirectoryChoice.choose(store: store, index: index) }
                    .disabled(!store.canChangeImageDirectory)
                if store.outputDirectory.standardizedFileURL != ImageLibrary.pictures().root.standardizedFileURL {
                    Button("Use Default") { ImageDirectoryChoice.confirm(nil, store: store, index: index) }
                        .disabled(!store.canChangeImageDirectory)
                }
            }
            if let progress = store.imageDirectoryProgress {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.caption)
                }
            } else if !store.canChangeImageDirectory {
                Text("Finish generation and queued work before changing this folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
