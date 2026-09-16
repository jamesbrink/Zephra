import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

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
    /// Where the window is looking, which owns whether this picker is up: it and the model
    /// browser are two sheets on one window, and `WorkspaceSelection` is what keeps them from
    /// stacking. See `showsReferencePicker` there.
    @Environment(WorkspaceSelection.self) private var workspace
    /// Whether a drop is in flight over the well right now, whichever of the three types below
    /// it turns out to be. Shared across all three so the empty and the filled state agree
    /// about it, and a replacement drop over an already-filled well shows the same accent.
    /// Which of the three drop destinations has a drop over it; the well is targeted while any
    /// does, so an exit from one arriving after an enter from another cannot turn the accent off.
    @State private var targeted: Set<Int> = []

    private var isTargeted: Bool { !targeted.isEmpty }

    var body: some View {
        @Bindable var workspace = workspace
        if store.descriptor.capabilities.supportsReferenceImage {
            well
                .dropDestination(for: LibraryItemReference.self) { references, _ in
                    guard let reference = references.first else { return false }
                    ReferenceAdoption.adopt(id: reference.id, into: store)
                    return true
                } isTargeted: { if $0 { targeted.insert(1) } else { targeted.remove(1) } }
                // Each drop is a choice made as it is accepted and read off the main actor:
                // `adoptReference` takes the ticket now and decodes in a detached task, so a
                // large photo never stalls the drop and a later choice still wins. A file
                // macOS cannot read leaves whatever was there alone.
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    store.adoptReference { ReferenceImageEncoder.pngData(contentsOf: url) }
                    return true
                } isTargeted: { if $0 { targeted.insert(2) } else { targeted.remove(2) } }
                .dropDestination(for: Data.self) { items, _ in
                    guard let data = items.first else { return false }
                    store.adoptReference { ReferenceImageEncoder.pngData(from: data) }
                    return true
                } isTargeted: { if $0 { targeted.insert(3) } else { targeted.remove(3) } }
                .sheet(isPresented: $workspace.showsReferencePicker) {
                    ReferencePickerSheet { item in ReferenceAdoption.adopt(item, into: store) }
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
    ///
    /// A replacement drop is legal here too, so the filled state answers `isTargeted` with the
    /// same accent stroke the empty well does — the well's shape is one thing wearing two
    /// pictures, not two different targets.
    private var filled: some View {
        ReferenceThumbnail()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous))
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    ReferenceAdoption.use(nil, into: store)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(ZephraChrome.badgeForeground, ZephraChrome.badgeBackdrop)
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .help("Clear the reference image")
            }
            .contextMenu {
                Button("From Library…") { workspace.showsReferencePicker = true }
                Button("Choose File…") { chooseFile() }
                Divider()
                Button("Clear") { ReferenceAdoption.use(nil, into: store) }
            }
            .accessibilityLabel(role.filledWellAccessibilityLabel)
    }

    private var empty: some View {
        Button {
            workspace.showsReferencePicker = true
        } label: {
            ReferencePlaceholder(title: role.wellCaption, isTargeted: isTargeted)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("From Library…") { workspace.showsReferencePicker = true }
            Button("Choose File…") { chooseFile() }
        }
        .help(role.emptyWellHelp)
        .accessibilityLabel(role.emptyWellHelp)
    }

    private var role: ReferenceRole {
        ReferenceRole(
            capabilities: store.descriptor.capabilities,
            continuing: store.settings.continuation != nil)
    }

    private func chooseFile() {
        Task {
            guard let url = await ReferenceImagePicker.choose(role: role) else { return }
            store.adoptReference { ReferenceImageEncoder.pngData(contentsOf: url) }
        }
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
            descriptor: PreviewModel.editing))
}
