import SwiftUI
import ZephraEngine

/// The picture a generation edits, on models that read one: a thumbnail at the trailing edge of
/// the prompt, a place to drop a file or a library picture, and a way to clear it. Shown only
/// for models that take a reference, so nothing offers a well that would do nothing.
///
/// Sized to the prompt band rather than to its own icon, so its right edge lines up with the
/// Generate button below it and the two read as one column.
///
/// Empty, it is a `Menu` with a primary action: clicking it opens the library picker straight
/// away, the more likely of the two sources, and the menu beside it names both. Filled, the
/// same two choices move into a context menu alongside Clear, since the thumbnail's own click
/// already does nothing worth taking.
struct ReferenceImageWell: View {
    @Environment(GenerationStore.self) private var store
    @Environment(ImageCache.self) private var cache

    @State private var isPickerPresented = false

    var body: some View {
        if store.descriptor.capabilities.supportsReferenceImage {
            well
                .dropDestination(for: LibraryItemReference.self) { references, _ in
                    guard let reference = references.first else { return false }
                    ReferenceAdoption.adopt(id: reference.id, into: store)
                    return true
                }
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
                .sheet(isPresented: $isPickerPresented) {
                    ReferencePickerSheet { item in ReferenceAdoption.adopt(item, into: store) }
                }
                // The `picker` screenshot build's one hook into this view's own state; see
                // `InterfacePreview.wantsReferencePicker`. False, and free, everywhere else.
                .onAppear {
                    if InterfacePreview.wantsReferencePicker { isPickerPresented = true }
                }
        }
    }

    @ViewBuilder
    private var well: some View {
        if let reference = store.settings.referenceImage,
           let bitmap = cache.thumbnail(forReference: reference) {
            filled(bitmap)
        } else {
            empty
        }
    }

    private func filled(_ bitmap: NSImage) -> some View {
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
            .contextMenu {
                Button("From Library…") { isPickerPresented = true }
                Button("Choose File…") { chooseFile() }
                Divider()
                Button("Clear") { store.useAsReference(nil) }
            }
            .accessibilityLabel("Reference image")
    }

    private var empty: some View {
        Menu {
            Button("From Library…") { isPickerPresented = true }
            Button("Choose File…") { chooseFile() }
        } label: {
            Image(systemName: "photo.badge.plus")
                .font(.title)
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } primaryAction: {
            isPickerPresented = true
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 64, height: 64)
        .help("Choose a picture to edit, or drop one here")
        .accessibilityLabel("Add a reference image")
    }

    private func chooseFile() {
        if let png = ReferenceImagePicker.choose() { store.useAsReference(png) }
    }
}

#Preview("Empty well") {
    ReferenceImageWell()
        .padding()
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(PreviewImages.library(count: 8))
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing))
}

#Preview("Filled well") {
    ReferenceImageWell()
        .padding()
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(PreviewImages.library(count: 8))
        .environment(GenerationStore.preview(
            state: .ready,
            image: PreviewImages.sample(reference: PreviewImages.referencePNG()),
            descriptor: PreviewModel.editing))
}
