import SwiftUI
import ZephraEngine

/// The picture a generation edits, on models that read one: a thumbnail at the trailing edge of
/// the prompt, a place to drop a file or a library picture, and a way to clear it. Shown only
/// for models that take a reference, so nothing offers a well that would do nothing.
///
/// Sized to the prompt band rather than to its own icon, so its right edge lines up with the
/// Generate button below it and the two read as one column.
///
/// Empty, a labelled button opens the picker with library and local-file choices. Filled, the
/// same two choices move into a context menu alongside Clear, since the thumbnail's own click
/// already does nothing worth taking.
struct ReferenceImageWell: View {
    @Environment(GenerationStore.self) private var store

    @State private var isPickerPresented = false

    var body: some View {
        if store.descriptor.capabilities.supportsReferenceImage {
            well
                .dropDestination(for: LibraryItemReference.self) { references, _ in
                    guard let reference = references.first else { return false }
                    ReferenceAdoption.adopt(id: reference.id, into: store)
                    return true
                }
                // Each drop is a choice made as it is accepted and read off the main actor:
                // `adoptReference` takes the ticket now and decodes in a detached task, so a
                // large photo never stalls the drop and a later choice still wins. A file
                // macOS cannot read leaves whatever was there alone.
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    store.adoptReference { ReferenceImageEncoder.pngData(contentsOf: url) }
                    return true
                }
                .dropDestination(for: Data.self) { items, _ in
                    guard let data = items.first else { return false }
                    store.adoptReference { ReferenceImageEncoder.pngData(from: data) }
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
        if store.settings.referenceImage != nil {
            filled
        } else {
            empty
        }
    }

    /// The picture itself is `ReferenceThumbnail`, which decodes it off the main actor and
    /// holds the square until it lands; this only frames it and hangs the controls on it.
    private var filled: some View {
        ReferenceThumbnail()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    ReferenceAdoption.use(nil, into: store)
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
                Button("Clear") { ReferenceAdoption.use(nil, into: store) }
            }
            .accessibilityLabel("Reference image")
    }

    private var empty: some View {
        Button {
            isPickerPresented = true
        } label: {
            ReferencePlaceholder()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("From Library…") { isPickerPresented = true }
            Button("Choose File…") { chooseFile() }
        }
        .help("Choose a picture to edit, or drop one here")
        .accessibilityLabel("Add a reference image")
    }

    private func chooseFile() {
        guard let url = ReferenceImagePicker.choose() else { return }
        store.adoptReference { ReferenceImageEncoder.pngData(contentsOf: url) }
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
