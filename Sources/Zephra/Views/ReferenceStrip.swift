import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The reference well on a model that reads several pictures: one tile per picture, in the order
/// the model reads them, and a `+` at the end while there is room for another.
///
/// Its width never moves past four tiles (`ReferenceStripLayout`), because the strip sits beside
/// the prompt in one row and ten tiles laid flat would take the capsule's whole width at the
/// 880-point window floor. Past four it scrolls sideways, which is the one axis a row of
/// thumbnails can afford to grow along.
///
/// The capsule's own row negotiates a continuous width, not a multiple of a tile — asked for
/// less than four tiles' worth of room, it used to hand the strip back a fractional one, and the
/// far tile showed sliced in half with nothing to say it scrolled. The fix leaves that
/// negotiation exactly as it was — the outer `.frame(minWidth:maxWidth:)` below is still asked
/// for the plain, unmeasured ceiling every render, so the row keeps deciding how much room this
/// view gets the way it always has, live to a resize either wider or narrower. `onGeometryChange`
/// only **watches** what that negotiation settled on (never a `GeometryReader`, which would ask
/// for the room itself and win the fight it is only meant to be observing) and
/// `ReferenceStripLayout.visibleTileCount(fitting:)` snaps it down to whole tiles; a `.mask`
/// then paints over whatever is past that snapped width, so the strip's own *size* stays fully
/// elastic (feeding the snapped value back into the frame would lock the strip at whatever it
/// first measured and it would never grow back on a later resize) while what is *drawn* always
/// stops on a tile's edge.
///
/// A `LazyHStack` inside a `ScrollView` rather than a `List`: a list would bring its own
/// selection, its own insets and its own vertical world, and the reorder here is a drag from one
/// tile onto another, which `ReferenceSlotReference` carries.
struct ReferenceStrip: View {
    @Environment(GenerationStore.self) private var store
    @State private var measuredWidth: CGFloat?

    var body: some View {
        let layout = layout
        let snappedWidth = layout.visibleWidth(fitting: measuredWidth)
        let scrolls = layout.scrolls(fitting: measuredWidth)
        ScrollView(.horizontal) {
            LazyHStack(spacing: ReferenceStripLayout.spacing) {
                ForEach(0..<store.settings.referenceImages.count, id: \.self) { index in
                    ReferenceTile(index: index)
                }
                if layout.showsAddTile {
                    ReferenceAddTile(title: addTitle)
                }
            }
            .frame(height: ReferenceStripLayout.tile)
            // Room for each tile's remove badge, which sits past the tile's top and trailing
            // edges: a scroll view clips to its bounds, and without this the badge was cut in
            // half along the top and past the last tile.
            .padding(.top, overhang)
            .padding(.trailing, overhang)
        }
        .scrollIndicators(.automatic)
        // Crops the far edge to a whole tile, with a static fade over its last few points
        // while there is more to scroll to — never an animation, since nothing in the app
        // target repeats. Leading-aligned: content rests flush with the strip's own leading
        // edge, so the snapped width is exactly what stays visible from there.
        .mask(alignment: .leading) { scrollMask(snappedWidth: snappedWidth, scrolls: scrolls) }
        .frame(
            minWidth: ReferenceStripLayout.tile + overhang, maxWidth: layout.visibleWidth,
            alignment: .trailing
        )
        .frame(height: ReferenceStripLayout.tile + overhang)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if measuredWidth != newWidth { measuredWidth = newWidth }
        }
        // The headroom is drawn, never laid out: the capsule's row sees the tiles' own footprint,
        // exactly as it did before there was any, and the badge overhangs it the way the single
        // well's does.
        .padding(.top, -overhang)
        .padding(.trailing, -overhang)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func scrollMask(snappedWidth: CGFloat, scrolls: Bool) -> some View {
        HStack(spacing: 0) {
            if scrolls {
                Rectangle()
                LinearGradient(
                    colors: [.black, .black.opacity(0)], startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 16)
            } else {
                Rectangle()
            }
        }
        .frame(width: snappedWidth)
    }

    private var overhang: CGFloat { ReferenceStripLayout.badgeOverhang }

    private var layout: ReferenceStripLayout {
        ReferenceStripLayout(
            pictures: store.settings.referenceImages.count, room: store.referenceRoom)
    }

    /// The add tile says what the well has always said while the strip is empty, and simply
    /// "Add" once there is something to add to — the role's word twice over would read as a
    /// second well rather than as one more slot of this one.
    private var addTitle: String {
        guard store.settings.referenceImages.isEmpty else { return "Add" }
        let capabilities = store.descriptor.capabilities
        return ReferenceRole(
            capabilities: capabilities, continuing: store.settings.continuation != nil
        ).wellCaption(count: capabilities.referenceImageCount.upperBound)
    }

    private var accessibilityLabel: String {
        let capabilities = store.descriptor.capabilities
        return ReferenceRole(
            capabilities: capabilities, continuing: store.settings.continuation != nil
        ).filledWellAccessibilityLabel(count: store.settings.referenceImages.count)
    }
}

#Preview("Strip") {
    ReferenceStrip()
        .padding()
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing))
}
