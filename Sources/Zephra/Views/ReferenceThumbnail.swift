import AppKit
import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The small picture in one slot of the reference well, decoded off the main actor.
///
/// Keyed on the store's choice ticket **and** this slot's position: `referenceChoice` moves on
/// every way a reference can be chosen or replaced, so the task restarts exactly when the
/// pictures change, and the SHA-256 that files it in `ImageCache` is never taken in `body`. The
/// position is in the key because one ticket covers the whole strip — a drop of five files is
/// one choice, by design — so without it the second tile would go on showing the picture that
/// was there before. A model switch that clamps the pictures away leaves the ticket alone,
/// which is fine: the well draws this view only while a picture is there.
struct ReferenceThumbnail: View {
    /// Which picture of the strip this is. Zero for the single well, which is the only slot
    /// every model before this one has ever had.
    var index: Int = 0

    @Environment(GenerationStore.self) private var store
    @Environment(ImageCache.self) private var cache
    @State private var bitmap: DrawnPicture?

    var body: some View {
        ground
            .overlay {
                if let bitmap {
                    Image(nsImage: bitmap.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .task(id: key) {
                bitmap = nil
                guard let picture, picture.hasPixels else { return }
                let made = await cache.referenceThumbnail(picture.data)
                guard !Task.isCancelled else { return }
                bitmap = made
            }
    }

    /// The picture this slot draws, or nil once the strip is shorter than the slot — which
    /// happens for one pass after a tile is removed, before the row is rebuilt.
    private var picture: ReferencePicture? {
        let pictures = store.settings.referenceImages
        return pictures.indices.contains(index) ? pictures[index] : nil
    }

    /// What a re-read is keyed on: the choice, this slot, and how long the strip is, since
    /// taking a tile out moves every picture after it without moving the ticket.
    private var key: Key {
        Key(
            choice: store.referenceChoice, index: index,
            pictures: store.settings.referenceImages.count)
    }

    private struct Key: Hashable {
        let choice: Int
        let index: Int
        let pictures: Int
    }

    /// The checkerboard behind a reference that carries transparency, and otherwise the well's
    /// own fill. A transparent reference is one this Mac can now make, so the well has to be
    /// able to say so.
    @ViewBuilder
    private var ground: some View {
        if bitmap?.hasAlpha == true {
            TransparencyGround()
        } else {
            Rectangle().fill(.quaternary)
        }
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
