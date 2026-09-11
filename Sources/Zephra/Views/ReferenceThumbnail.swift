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
    @State private var bitmap: NSImage?

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let bitmap {
                    Image(nsImage: bitmap)
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
