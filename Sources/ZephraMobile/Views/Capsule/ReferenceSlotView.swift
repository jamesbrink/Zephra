import SwiftUI
import ZephraCore
import ZephraStyle

/// One place in the well: the picture that is in it, or the glyph that says there is none.
///
/// The Mac's slot in a phone's shape. It draws and nothing else — the strip above it owns the
/// order, the doors and the draft — so the single well and every tile of a strip are one tile
/// with one set of numbers behind them.
struct ReferenceSlotView: View {
    /// The picture here, or nil for an empty well.
    let picture: ReferencePicture?
    /// What taking this one out does, or nil where there is nothing to take out: the single
    /// well has its own Clear beside the doors.
    var remove: (() -> Void)?

    var body: some View {
        tile
            .frame(width: 72, height: 72)
            .clipShape(
                RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous)
            )
            .overlay(alignment: .topTrailing) { removeButton }
    }

    @ViewBuilder private var tile: some View {
        if let picture, picture.hasPixels {
            ReferenceThumbnail(data: picture.data)
        } else {
            RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous)
                .fill(ZephraChrome.wellFill)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
        }
    }

    @ViewBuilder private var removeButton: some View {
        if let remove, picture != nil {
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding(3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take this picture out")
        }
    }
}
