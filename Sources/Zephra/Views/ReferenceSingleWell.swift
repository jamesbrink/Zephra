import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The one-picture well, exactly as every model before this one drew it.
///
/// Empty, a labelled button opens the picker with library and local-file choices. Filled, the
/// same two choices move into a context menu alongside Clear, since the thumbnail's own click
/// already does nothing worth taking. A replacement drop is legal in both states, so both wear
/// the same accent: the well's shape is one thing wearing two pictures, not two targets.
///
/// Its own file so `ReferenceImageWell` keeps to the one decision it is left with — strip or
/// well — and so this shape cannot drift as the strip beside it changes.
struct ReferenceSingleWell: View {
    /// Whether a drop is in flight over the well right now, whichever of its three types.
    let isTargeted: Bool

    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
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
            .frame(width: ReferenceStripLayout.tile, height: ReferenceStripLayout.tile)
            .clipShape(shape)
            .overlay {
                if isTargeted {
                    shape.strokeBorder(Color.accentColor, lineWidth: 1).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) { clearButton }
            .contextMenu {
                Button("From Library…") { workspace.showsReferencePicker = true }
                Button("Choose File…") { chooseFile() }
                Divider()
                Button("Clear") { ReferenceAdoption.use(nil, into: store) }
            }
            .accessibilityLabel(role.filledWellAccessibilityLabel)
    }

    private var clearButton: some View {
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

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous)
    }

    private var role: ReferenceRole {
        ReferenceRole(
            capabilities: store.descriptor.capabilities,
            continuing: store.settings.continuation != nil)
    }

    private func chooseFile() {
        Task {
            guard let url = await ReferenceImagePicker.choose(role: role, upTo: 1).first else {
                return
            }
            store.adoptReference { ReferenceImageEncoder.pngData(contentsOf: url) }
        }
    }
}
