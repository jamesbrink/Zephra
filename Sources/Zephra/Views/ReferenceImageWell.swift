import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The picture or pictures a generation edits, on models that read any: at the trailing edge of
/// the prompt, a place to drop files or library pictures, and a way to clear them. Shown only
/// for models that take a reference, so nothing offers a well that would do nothing.
///
/// Sized to the prompt band rather than to its own icon, so its right edge lines up with the
/// Generate button below it and the two read as one column.
///
/// What is decided here is the shape and the doors, and nothing else: a model that reads several
/// pictures draws `ReferenceStrip`, a model that reads one draws `ReferenceSingleWell` — which is
/// byte for byte the well every model before this one had — and `ReferenceNotes` puts under
/// either one whatever the store or the pictures' own headers have to say.
///
/// The three drop destinations take **every** item dropped rather than the first, through one
/// `adoptReferences` claim: a drop of five files is one choice and has to land as one.
struct ReferenceImageWell: View {
    @Environment(GenerationStore.self) private var store
    /// Where the window is looking, which owns whether this picker is up: it and the model
    /// browser are two sheets on one window, and `WorkspaceSelection` is what keeps them from
    /// stacking. See `showsReferencePicker` there.
    @Environment(WorkspaceSelection.self) private var workspace
    /// Which of the three drop destinations has a drop over it; the well is targeted while any
    /// does, so an exit from one arriving after an enter from another cannot turn the accent off.
    @State private var targeted: Set<Int> = []

    var body: some View {
        @Bindable var workspace = workspace
        if store.descriptor.capabilities.supportsReferenceImage {
            well
                .modifier(ReferenceNotes())
                .dropDestination(for: LibraryItemReference.self) { references, _ in
                    guard !references.isEmpty else { return false }
                    ReferenceAdoption.adopt(ids: references.map(\.id), into: store)
                    return true
                } isTargeted: { if $0 { targeted.insert(1) } else { targeted.remove(1) } }
                // Each drop is a choice made as it is accepted and read off the main actor:
                // the claim is taken now and the bytes are decoded in a detached task, so a
                // large photo never stalls the drop and a later choice still wins. A file
                // macOS cannot read leaves whatever was there alone.
                .dropDestination(for: URL.self) { urls, _ in
                    guard !urls.isEmpty else { return false }
                    ReferenceAdoption.adopt(urls: urls, into: store)
                    return true
                } isTargeted: { if $0 { targeted.insert(2) } else { targeted.remove(2) } }
                .dropDestination(for: Data.self) { items, _ in
                    guard !items.isEmpty else { return false }
                    ReferenceAdoption.adopt(bytes: items, into: store)
                    return true
                } isTargeted: { if $0 { targeted.insert(3) } else { targeted.remove(3) } }
                .sheet(isPresented: $workspace.showsReferencePicker) {
                    ReferencePickerSheet(limit: pickerLimit) { items in
                        ReferenceAdoption.adopt(items, into: store)
                    }
                }
        }
    }

    @ViewBuilder
    private var well: some View {
        if ReferenceStripLayout.drawsStrip(capabilities: store.descriptor.capabilities) {
            ReferenceStrip()
        } else {
            ReferenceSingleWell(isTargeted: !targeted.isEmpty)
        }
    }

    /// How many pictures the picker's Use button may hand over at once: what the model would
    /// read in all, not what is left, since the picker's selection is made before anything is
    /// taken out and the store trims what will not fit and says so.
    private var pickerLimit: Int {
        min(
            store.descriptor.capabilities.referenceImageCount.upperBound,
            ReferenceLimits.maximumPictures)
    }
}

#Preview("Empty well") {
    ReferenceImageWell()
        .padding()
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(PreviewImages.library(count: 8))
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing))
}

#Preview("Filled well") {
    ReferenceImageWell()
        .padding()
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(PreviewImages.library(count: 8))
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(
            state: .ready,
            image: PreviewImages.sample(reference: PreviewImages.referencePNG()),
            descriptor: PreviewModel.video))
}
