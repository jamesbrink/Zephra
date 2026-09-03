import SwiftUI
import ZephraEngine

/// The things to do with the image being looked at, at the foot of the inspector.
///
/// Opening is the prominent one and takes Return, because it is what the column is usually
/// leading up to: you looked at the facts, and this is the one. The rest are equals beneath it.
///
/// "Use as reference" appears only on a model that reads one, so a build running Z-Image alone
/// never shows a button that could not do anything.
struct InspectorActions: View {
    /// The image the buttons act on.
    let item: LibraryItem

    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            LibraryOpenButton(item: item)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                QueueVariationButton(item: item)
                    .frame(maxWidth: .infinity)
                Button("Reveal in Finder") {
                    ImageExport.revealInFinder(files: [item.url])
                }
                .frame(maxWidth: .infinity)
            }
            if store.descriptor.capabilities.supportsReferenceImage {
                UseAsReferenceButton(item: item)
                    .frame(maxWidth: .infinity)
            }
        }
        .lineLimit(1)
    }
}

#Preview("Actions") {
    InspectorActions(item: PreviewImages.library(count: 1).items[0])
        .padding(18)
        .frame(width: 320)
        .environment(GenerationStore.preview(state: .ready))
}
