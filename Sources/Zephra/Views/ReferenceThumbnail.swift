import AppKit
import SwiftUI
import ZephraEngine
import ZephraStyle

/// The small picture in the reference well, decoded off the main actor.
///
/// Keyed on the store's choice ticket rather than on the bytes: `referenceChoice` moves on
/// every way a reference can be chosen or replaced, so the task restarts exactly when the
/// picture changes, and the SHA-256 that files it in `ImageCache` is never taken in `body`.
/// A model switch that clamps the picture away leaves the ticket alone, which is fine: the
/// well shows this view only while a picture is there.
struct ReferenceThumbnail: View {
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
            .task(id: store.referenceChoice) {
                guard let png = store.settings.referenceImage else { return }
                bitmap = await cache.referenceThumbnail(png)
            }
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
