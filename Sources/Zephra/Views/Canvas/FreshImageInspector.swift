import SwiftUI
import ZephraCore
import ZephraEngine

/// A picture the session made and the library has not indexed yet, at length: the picture,
/// what it was asked for, and how it was made.
///
/// The same shape as `SingleImageInspector`, without the tags and albums: those are written
/// into the file's own chunk, and there is no indexed file to write them to. The moment the
/// scan lands, `CanvasInspector` swaps this for the library's own.
struct FreshImageInspector: View {
    /// The picture on the canvas.
    let image: GeneratedImage
    @Environment(\.seedFormat) private var seedFormat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                picture
                if !image.settings.prompt.isEmpty {
                    Text(image.settings.prompt)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ImageFactsView(facts: facts, edited: image.settings.referenceImage != nil)
                Spacer(minLength: 8)
                FreshImageActions(image: image)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var picture: some View {
        SessionImage(request: .full(image))
            .clipShape(
                RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
            )
    }

    private var facts: ImageFacts {
        ImageFacts(
            image, modelName: ModelCatalog.descriptor(id: image.modelID)?.fullName,
            seedFormat: seedFormat)
    }
}

#Preview("Fresh") {
    FreshImageInspector(image: PreviewImages.sample())
        .frame(width: 320, height: 700)
        .environment(ImageCache())
        .environment(GenerationStore.preview(state: .ready))
}
