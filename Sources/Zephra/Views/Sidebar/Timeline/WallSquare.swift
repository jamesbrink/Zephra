import SwiftUI
import ZephraEngine

/// One square of the wall: the tile, a wash while the pointer is over it, and a ring when it is
/// the picture the canvas is showing — the last two through `WallSquareChrome`, which is also
/// where the rule that neither takes the click lives.
///
/// The wash is what says a square can be pressed, the way Photos lifts a thumbnail under the
/// pointer; without it the wall read as a contact sheet. It comes and goes at once, the way
/// AppKit's own hover highlights do, rather than fading: a fade would want Reduce Motion
/// honoured, and a fourth stored property for a twelfth of a second is not worth it. The
/// ring is the same one the library
/// grid draws round a selected cell, a point outside the square, so "this one is on the
/// canvas" looks the same in both places. A place still to be filled takes neither: there is
/// nothing to press and nothing to show.
struct WallSquare: View {
    /// What this square stands for.
    let tile: TimelineTile
    /// Whether the canvas is showing this square's file.
    let isShowing: Bool

    @State private var isHovered = false

    var body: some View {
        RunTile(tile: tile)
            .modifier(WallSquareChrome(isHovered: isHovered, isShowing: isShowing))
            .onHover { over in
                guard isPressable else { return }
                isHovered = over
            }
            .accessibilityAddTraits(isShowing ? .isSelected : [])
    }

    private var isPressable: Bool {
        if case .pending = tile { return false }
        return true
    }
}

#Preview("Squares") {
    HStack(spacing: 4) {
        WallSquare(tile: .item(PreviewImages.library(count: 1).items[0]), isShowing: true)
        WallSquare(tile: .fresh(PreviewImages.sample()), isShowing: false)
        WallSquare(tile: .pending(2), isShowing: false)
    }
    .frame(width: 248)
    .padding()
    .background(Color.canvasBackground)
    .environment(ImageCache())
    .environment(ThumbnailCache())
    .environment(GenerationStore.preview(state: .ready))
}
