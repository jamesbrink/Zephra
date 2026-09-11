import SwiftUI
import ZephraStyle

/// What `WallSquare` lays over its tile: the wash while the pointer is over it, and the ring
/// when the canvas is showing it. Both draw in front of the tile's button, and neither may take
/// the click.
///
/// A filled shape in an overlay is what the pointer hits, and the wash is up exactly when the
/// pointer is over the square, so without `allowsHitTesting(false)` every click on the wall
/// landed on the wash and the button under it never heard one. An accessibility press goes
/// straight to the action, which is how the hands-off checks passed while a real click did
/// nothing. `WallSquareChromeTests` clicks a hosted button through this chrome, and
/// `make lint-layers` keeps `hoverWash` from being laid over anything anywhere else.
struct WallSquareChrome: ViewModifier {
    /// Whether the pointer is over the square.
    let isHovered: Bool
    /// Whether the canvas is showing this square's file.
    let isShowing: Bool

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .overlay {
                if isHovered {
                    ZStack {
                        shape.fill(ZephraChrome.hoverWash)
                        shape.strokeBorder(ZephraChrome.hairline, lineWidth: 1)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if isShowing {
                    RoundedRectangle(cornerRadius: ZephraChrome.tileRadius + 1, style: .continuous)
                        .inset(by: -1)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ZephraChrome.tileRadius, style: .continuous)
    }
}
