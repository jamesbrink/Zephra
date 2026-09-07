import SwiftUI

/// The reference well's empty state, and its filled state's drop target too: a plain macOS
/// drop well rather than a solid card, legible over the floating capsule's material without
/// competing with it.
///
/// Dashed rather than solid, because there is nothing here yet to divide from anything; the
/// stroke and the fill both answer `isTargeted` — a drop really in flight over the well — by
/// going solid and accented, the way a drop zone stakes its claim, so a replacement drop over
/// an already-filled well reads the same way. The hover lift is instant, like `WallSquare`'s
/// wash: a fade would want Reduce Motion honoured, and a fourth stored property for a twelfth
/// of a second is not worth it here either. Neither the stroke nor the fill may take the click,
/// the way `WallSquareChrome` never does; `ReferencePlaceholderChromeTests` pins it.
///
/// Plain parameters only — this lives in `Style/`, which knows nothing about a model's
/// capabilities or the store. The caller owns `.help` and `.accessibilityLabel` on the button
/// that wraps this, since those describe the action, not the shape.
struct ReferencePlaceholder: View {
    /// The caption under the glyph. A later milestone renames it by model role; the default
    /// keeps every existing call site unchanged until then.
    var title: String = "Reference"
    /// Whether a drop is in flight over this well right now.
    let isTargeted: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "photo.badge.plus")
                .font(.title3)
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(width: 64, height: 64)
        .background(fill, in: shape)
        .overlay {
            shape
                .strokeBorder(
                    isTargeted ? Color.accentColor : ZephraChrome.wellDash,
                    style: isTargeted
                        ? StrokeStyle(lineWidth: 1)
                        : StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if isTargeted { return ZephraChrome.wellFillTargeted }
        return isHovered ? ZephraChrome.wellFillHovered : ZephraChrome.wellFill
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous)
    }
}

#Preview("Empty well states") {
    HStack(spacing: 16) {
        ReferencePlaceholder(isTargeted: false)
        ReferencePlaceholder(isTargeted: true)
    }
    .padding()
}
