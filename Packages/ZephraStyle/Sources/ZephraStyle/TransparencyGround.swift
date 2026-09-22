import SwiftUI
import ZephraCore

/// The checkered ground a transparent picture is drawn over, in both apps.
///
/// `Checkerboard`'s rule in colour sets that follow the appearance: paper greys in the light
/// one, two close darks in the dark one rather than the light pair inverted, because the ground
/// is a surface the picture sits on and not a light behind it.
///
/// A `Canvas` and never a `TimelineView`: the ground is drawn once per layout and never again,
/// which is what the app targets' repeating-animation ban asks of everything on screen. It is
/// drawn **only behind a picture that has alpha** — a checkerboard under every opaque picture
/// would be a change to every model that came before this one.
public struct TransparencyGround: View {
    /// A ground. It holds nothing: the pattern is `Checkerboard`'s and the colours are the
    /// palette's.
    public init() {}

    public var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            let cell = CGFloat(Checkerboard.cell)
            context.fill(
                Path(CGRect(origin: .zero, size: size)), with: .color(.transparencyLight))
            var squares = Path()
            var row = 0
            while CGFloat(row) * cell < size.height {
                var column = 0
                while CGFloat(column) * cell < size.width {
                    if !Checkerboard.isLight(
                        x: column * Checkerboard.cell, y: row * Checkerboard.cell)
                    {
                        squares.addRect(
                            CGRect(
                                x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                width: cell, height: cell))
                    }
                    column += 1
                }
                row += 1
            }
            context.fill(squares, with: .color(.transparencyDark))
        }
        .accessibilityHidden(true)
    }
}

#Preview("Transparency ground") {
    VStack(spacing: 0) {
        TransparencyGround()
            .frame(width: 240, height: 120)
        TransparencyGround()
            .frame(width: 240, height: 120)
            .environment(\.colorScheme, .dark)
    }
    .padding(24)
}
