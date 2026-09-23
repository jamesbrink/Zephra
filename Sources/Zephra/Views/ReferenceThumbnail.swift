import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The small picture in one slot of the reference well, decoded off the main actor.
///
/// Keyed on the store's choice ticket, the strip's revision **and** this slot's position:
/// `referenceChoice` moves on every way a reference can be chosen or replaced and
/// `referenceRevision` on every change to the list — a reorder included, which moves neither the
/// ticket nor the count — so the task restarts exactly when the pictures change, and the SHA-256
/// that files it in `ImageCache` is never taken in `body`. The position is in the key because one
/// ticket covers the whole strip — a drop of five files is one choice, by design — so without it
/// the second tile would go on showing the picture that was there before. The drawing is
/// `ReferenceThumbnailImage`, which this view only hands the slot's picture and key.
struct ReferenceThumbnail: View {
    /// Which picture of the strip this is. Zero for the single well, which is the only slot
    /// every model before this one has ever had.
    var index: Int = 0

    @Environment(GenerationStore.self) private var store

    var body: some View {
        ReferenceThumbnailImage(request: request)
    }

    /// The picture this slot draws — nil once the strip is shorter than the slot, which happens
    /// for one pass after a tile is removed, before the row is rebuilt — and the key it is read
    /// under.
    private var request: ReferenceThumbnailImage.Request {
        let pictures = store.settings.referenceImages
        return ReferenceThumbnailImage.Request(
            picture: pictures.indices.contains(index) ? pictures[index] : nil,
            key: ReferenceThumbnailImage.Key(
                choice: store.referenceChoice, revision: store.referenceRevision,
                index: index, pictures: pictures.count))
    }
}

#Preview("Reference thumbnail") {
    ReferenceThumbnail()
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous))
        .padding()
        .environment(ImageCache())
        .environment(GenerationStore.preview(
            state: .ready,
            image: PreviewImages.sample(reference: PreviewImages.referencePNG()),
            descriptor: PreviewModel.editing))
}
