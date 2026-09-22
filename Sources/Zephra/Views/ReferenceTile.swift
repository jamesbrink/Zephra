import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// One picture of the reference strip: the thumbnail, a way to take it out, a way to drag it
/// somewhere else in the strip, and a menu saying in words what the drag says with the mouse.
///
/// The order of the strip is the order the model reads the pictures in, so moving one is a
/// choice about the request rather than about the view — which is why it goes through
/// `GenerationStore.moveReference(from:to:)` and why "Move Left" and "Move Right" are in the
/// menu: a reorder nobody can do without a mouse is a reorder half the people cannot do.
///
/// Three stored properties, at the limit: the slot, the store, and whether the pointer is over
/// it. The decode belongs to `ReferenceThumbnail`, which holds its own.
struct ReferenceTile: View {
    /// Which picture of the strip this is.
    let index: Int

    @Environment(GenerationStore.self) private var store
    @State private var isHovering = false

    var body: some View {
        ReferenceThumbnail(index: index)
            .frame(width: ReferenceStripLayout.tile, height: ReferenceStripLayout.tile)
            .clipShape(shape)
            .overlay {
                shape
                    .strokeBorder(ZephraChrome.wellDash, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) { if isHovering { removeButton } }
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .help(tooltip)
            .accessibilityLabel(accessibilityLabel)
            .draggable(ReferenceSlotReference(index: index))
            .dropDestination(for: ReferenceSlotReference.self) { slots, _ in
                guard let from = slots.first?.index, from != index else { return false }
                // `moveReference` takes an insertion offset, so landing *on* this tile means
                // one past it when the picture is travelling forwards and this one when it is
                // travelling back.
                store.moveReference(from: from, to: from < index ? index + 1 : index)
                return true
            }
            .contextMenu { menu }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous)
    }

    private var removeButton: some View {
        Button {
            store.removeReference(at: index)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(ZephraChrome.badgeForeground, ZephraChrome.badgeBackdrop)
        }
        .buttonStyle(.plain)
        .offset(x: 5, y: -5)
        .help("Remove this reference picture")
        .accessibilityLabel("Remove reference \(index + 1)")
    }

    @ViewBuilder
    private var menu: some View {
        Button("Move Left") { store.moveReference(from: index, to: index - 1) }
            .disabled(index == 0)
        Button("Move Right") { store.moveReference(from: index, to: index + 2) }
            .disabled(index >= store.settings.referenceImages.count - 1)
        Divider()
        Button("Replace…") { replace() }
        Button("Remove") { store.removeReference(at: index) }
    }

    /// Where this picture came from, which is the only thing about it the tile cannot show.
    private var tooltip: String {
        let pictures = store.settings.referenceImages
        guard pictures.indices.contains(index) else { return "" }
        let picture = pictures[index]
        if let origin = picture.origin { return origin }
        guard let size = picture.size else { return accessibilityLabel }
        return "\(accessibilityLabel) \(ImageFacts.separator) \(size.width) \u{00D7} \(size.height)"
    }

    private var accessibilityLabel: String {
        "Reference \(index + 1) of \(store.settings.referenceImages.count)"
    }

    private func replace() {
        let role = ReferenceRole(
            capabilities: store.descriptor.capabilities,
            continuing: store.settings.continuation != nil)
        Task {
            guard let url = await ReferenceImagePicker.choose(role: role, upTo: 1).first else {
                return
            }
            let ticket = store.claimReference()
            let picture = await Task.detached(priority: .userInitiated) {
                ReferenceImageEncoder.picture(contentsOf: url)
            }.value
            guard let picture else { return }
            store.replaceReference(at: index, with: picture, ticket: ticket)
        }
    }
}
