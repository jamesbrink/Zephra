import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The reference well on a model that reads several pictures: one tile per picture, in the order
/// the model reads them, and a `+` at the end while there is room for another.
///
/// Its width never moves past four tiles (`ReferenceStripLayout`), because the strip sits beside
/// the prompt in one row and ten tiles laid flat would take the capsule's whole width at the
/// 880-point window floor. Past four it scrolls sideways, which is the one axis a row of
/// thumbnails can afford to grow along.
///
/// A `LazyHStack` inside a `ScrollView` rather than a `List`: a list would bring its own
/// selection, its own insets and its own vertical world, and the reorder here is a drag from one
/// tile onto another, which `ReferenceSlotReference` carries.
struct ReferenceStrip: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        let layout = layout
        ScrollView(.horizontal) {
            LazyHStack(spacing: ReferenceStripLayout.spacing) {
                ForEach(0..<store.settings.referenceImages.count, id: \.self) { index in
                    ReferenceTile(index: index)
                }
                if layout.showsAddTile {
                    ReferenceAddTile(title: addTitle)
                }
            }
            .frame(height: ReferenceStripLayout.tile)
        }
        .scrollDisabled(!layout.scrolls)
        .scrollIndicators(layout.scrolls ? .visible : .hidden)
        .frame(width: layout.visibleWidth, height: ReferenceStripLayout.tile)
        .accessibilityLabel(accessibilityLabel)
    }

    private var layout: ReferenceStripLayout {
        ReferenceStripLayout(
            pictures: store.settings.referenceImages.count, room: store.referenceRoom)
    }

    /// The add tile says what the well has always said while the strip is empty, and simply
    /// "Add" once there is something to add to — the role's word twice over would read as a
    /// second well rather than as one more slot of this one.
    private var addTitle: String {
        guard store.settings.referenceImages.isEmpty else { return "Add" }
        let capabilities = store.descriptor.capabilities
        return ReferenceRole(
            capabilities: capabilities, continuing: store.settings.continuation != nil
        ).wellCaption(count: capabilities.referenceImageCount.upperBound)
    }

    private var accessibilityLabel: String {
        let capabilities = store.descriptor.capabilities
        return ReferenceRole(
            capabilities: capabilities, continuing: store.settings.continuation != nil
        ).filledWellAccessibilityLabel(count: store.settings.referenceImages.count)
    }
}

#Preview("Strip") {
    ReferenceStrip()
        .padding()
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing))
}
