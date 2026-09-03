import SwiftUI
import ZephraEngine

/// The picture a generation edits, on models that read one: a thumbnail at the trailing edge of
/// the prompt, a place to drop a file, and a way to clear it. Shown only for models that take a
/// reference, so nothing offers a well that would do nothing.
///
/// Sized to the prompt band rather than to its own icon, so its right edge lines up with the
/// Generate button below it and the two read as one column.
struct ReferenceImageWell: View {
    @Environment(GenerationStore.self) private var store
    @Environment(ImageCache.self) private var cache

    var body: some View {
        if store.descriptor.capabilities.supportsReferenceImage {
            well
                .dropDestination(for: URL.self) { urls, _ in
                    // Read inside the closure: a dropped file's read grant lasts the drop.
                    // A file macOS cannot read leaves whatever was there alone.
                    guard let url = urls.first,
                          let png = ReferenceImageEncoder.pngData(contentsOf: url)
                    else { return false }
                    store.useAsReference(png)
                    return true
                }
                .dropDestination(for: Data.self) { items, _ in
                    guard let data = items.first,
                          let png = ReferenceImageEncoder.pngData(from: data)
                    else { return false }
                    store.useAsReference(png)
                    return true
                }
        }
    }

    @ViewBuilder
    private var well: some View {
        if let reference = store.settings.referenceImage,
           let bitmap = cache.thumbnail(forReference: reference) {
            Image(nsImage: bitmap)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        store.useAsReference(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .help("Clear the reference image")
                }
                .accessibilityLabel("Reference image")
        } else {
            Button {
                if let png = ReferenceImagePicker.choose() { store.useAsReference(png) }
            } label: {
                Image(systemName: "photo.badge.plus")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Choose a picture to edit, or drop one here")
            .accessibilityLabel("Add a reference image")
        }
    }
}

#Preview("Empty well") {
    ReferenceImageWell()
        .padding()
        .environment(ImageCache())
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing))
}

#Preview("Filled well") {
    ReferenceImageWell()
        .padding()
        .environment(ImageCache())
        .environment(GenerationStore.preview(
            state: .ready,
            image: PreviewImages.sample(reference: PreviewImages.referencePNG()),
            descriptor: PreviewModel.editing))
}
