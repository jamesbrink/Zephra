import SwiftUI

/// Where the viewer stands: which picture is up, whether the chrome is, whether the picture is
/// zoomed, and how far it has been pulled down towards closing.
///
/// One value rather than four `@State`s, so the viewer holds two stored properties and the
/// rules about pulling a picture down are a type with a test rather than lines in a gesture.
struct ViewerPose {
    /// The file name of the picture on screen; nil before the pager has settled.
    var current: String?
    /// Whether a tap has put the title strip and the bar away.
    var chromeIsHidden = false
    /// Whether the picture is in past fit, which is when a drag pans it rather than pulling it.
    var isZoomed = false
    /// How far down the picture has been pulled, and along which axis the drag went.
    var pull = Pull()

    /// One pull of the picture towards the bottom of the screen.
    ///
    /// The axis is decided once per drag, from the first movement past the gesture's
    /// minimum, and never revisited: a drag that began sideways is the pager's however far
    /// down it wanders, and one that began downwards is a pull however far it drifts. Two
    /// gestures reading one finger have to agree on whose it is, and this is how.
    struct Pull: Equatable {
        /// How far down the picture has gone, never negative.
        var offset: CGFloat = 0
        /// Whose drag this is, or nil before it has moved enough to say.
        var axis: Axis?

        /// How far along the pull is, 0 at rest and 1 at the distance that closes the viewer.
        var progress: CGFloat {
            min(1, max(0, offset / MobileChrome.viewerDismissDistance))
        }

        /// The axis a drag has taken: whichever component is larger, and a tie is vertical,
        /// since a finger that has not decided is not swiping between pictures.
        static func axis(for translation: CGSize) -> Axis {
            abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
        }

        /// Whether letting go here closes the viewer: past the distance, or flung so that it
        /// would have been well past it.
        static func shouldDismiss(offset: CGFloat, predicted: CGFloat) -> Bool {
            offset >= MobileChrome.viewerDismissDistance
                || predicted >= 2 * MobileChrome.viewerDismissDistance
        }

        /// Follows one change of the drag, locking the axis on the first.
        mutating func follow(_ translation: CGSize) {
            if axis == nil { axis = Self.axis(for: translation) }
            guard axis == .vertical else { return }
            offset = max(0, translation.height)
        }

        /// Lets go: back to rest, with the axis free for the next drag.
        mutating func release() {
            offset = 0
            axis = nil
        }
    }
}
