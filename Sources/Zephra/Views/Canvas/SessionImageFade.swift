import SwiftUI

/// The one orchestrated motion in the app: a finished picture fades up over 250 ms.
///
/// Only the canvas's whole picture fades; a thumbnail simply appears, since a wall of them
/// fading in at their own moments would be a twinkle rather than a reveal. A picture the
/// cache already held is on screen before the trigger moves, so it does not fade either —
/// stepping back through history is a look, not an arrival. Reduce Motion turns the fade off,
/// which the modifier reads for itself so the view over it stays within its three properties.
struct SessionImageFade: ViewModifier {
    /// Whether this kind of picture fades at all.
    let fades: Bool
    /// What changes when the pixels land; the fade runs on that change and no other.
    let trigger: ImageCache.Request.Key?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(animation, value: trigger)
    }

    private var animation: Animation? {
        fades && !reduceMotion ? .easeOut(duration: 0.25) : nil
    }
}
