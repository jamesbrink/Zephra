import SwiftUI

/// One picture, pinched to zoom and dragged around once it is zoomed.
///
/// The zoom springs back to fit when it is let go under 1, and the offset goes with it, so
/// there is no state anybody can leave the picture in that they cannot get out of. Nothing
/// animates on its own: the only motion here is the one somebody's fingers are making, and
/// under Reduce Motion the spring back is instant rather than sprung.
struct ZoomablePicture: View {
    /// The picture's bytes.
    let data: Data

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far in, and how far along. One value, because they are settled together.
    @State private var zoom = PictureZoom()

    var body: some View {
        picture
            .scaleEffect(zoom.scale)
            .offset(zoom.offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { zoom.magnify(to: $0.magnification) }
                    .onEnded { _ in settle() }
                    .simultaneously(
                        with: DragGesture()
                            .onChanged { zoom.drag(by: $0.translation) }
                            .onEnded { _ in settle() })
            )
            .onTapGesture(count: 2) { withAnimation(motion) { zoom.toggle() } }
            .accessibilityLabel("Picture")
    }

    @ViewBuilder private var picture: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Color.black
        }
    }

    /// Puts the picture back where it can be seen, once the fingers are off it.
    private func settle() {
        withAnimation(motion) { zoom.settle() }
    }

    /// The spring, or none at all where somebody has asked for less movement.
    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.25)
    }
}

/// How far into a picture somebody has zoomed, and how far they have pushed it.
struct PictureZoom {
    /// The scale as it stands.
    private(set) var scale: CGFloat = 1
    /// How far the picture has been pushed from the middle.
    private(set) var offset: CGSize = .zero
    /// The scale the last gesture ended at, which the next one multiplies.
    private var committed: CGFloat = 1
    private var committedOffset: CGSize = .zero

    /// The furthest in anybody may go: past this the pixels are the model's rather than the
    /// picture's, and a phone screen has no more to show.
    static let maximum: CGFloat = 6

    /// Follows a pinch.
    mutating func magnify(to magnification: CGFloat) {
        scale = min(Self.maximum, max(0.5, committed * magnification))
    }

    /// Follows a drag, which does nothing at all while the picture fits.
    mutating func drag(by translation: CGSize) {
        guard scale > 1 else { return }
        offset = CGSize(
            width: committedOffset.width + translation.width,
            height: committedOffset.height + translation.height)
    }

    /// Springs back to fit when the picture has been let go smaller than it started.
    mutating func settle() {
        if scale <= 1 {
            scale = 1
            offset = .zero
        }
        committed = scale
        committedOffset = offset
    }

    /// A double tap: all the way in, or all the way back.
    mutating func toggle() {
        scale = scale > 1 ? 1 : 2.5
        offset = .zero
        committed = scale
        committedOffset = .zero
    }
}
