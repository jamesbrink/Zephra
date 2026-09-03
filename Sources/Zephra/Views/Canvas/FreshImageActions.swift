import SwiftUI
import ZephraCore
import ZephraEngine

/// The things to do with a picture the session holds in memory, at the foot of the inspector:
/// the same four the picture's own context menu offers, as buttons.
struct FreshImageActions: View {
    /// The picture the buttons act on.
    let image: GeneratedImage

    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Save as…") { ImageExport.saveAs(image) }
                    .frame(maxWidth: .infinity)
                Button("Copy") { ImageExport.copyToPasteboard(image) }
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                Button("Reveal in Finder") { ImageExport.revealInFinder(image) }
                    .frame(maxWidth: .infinity)
                    .disabled(image.fileURL == nil)
                if store.descriptor.capabilities.supportsReferenceImage {
                    Button("Use as reference") { store.useAsReference(image.pngData) }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .lineLimit(1)
    }
}

#Preview("Actions") {
    FreshImageActions(image: PreviewImages.sample())
        .padding(18)
        .frame(width: 320)
        .environment(GenerationStore.preview(state: .ready))
}
