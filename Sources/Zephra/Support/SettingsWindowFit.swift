import CoreGraphics

/// How big the Settings window may actually be, given the tab showing and the display it is on.
///
/// A tab says how tall it would like to stand (`SettingsTab.openingHeight`), and Performance's
/// 1010 points plus the window's 88 of chrome is past what a 1728 x 1080-point display has once
/// the menu bar is off it. Asking for that size anyway put the tab's bottom below the screen:
/// AppKit clamps a window to the visible frame only while the minimum size it is holding to
/// actually fits, and the frame used to pin `contentMinSize` at the tab's own height, so there
/// was nothing to clamp to. The answer is to ask for a size that fits in the first place; the
/// tab's content already scrolls, so what does not fit is scrolled to rather than lost.
///
/// Pure arithmetic on purpose, so every case is a test rather than a display nobody here has.
enum SettingsWindowFit {
    /// The content size to open a tab at: its own height where the display has room, the room
    /// the display has otherwise, and never less than the floor the window may be dragged to.
    ///
    /// The floor wins over the display because a window smaller than its own minimum is a
    /// window AppKit will grow back anyway; on a display that small the person scrolls and
    /// moves the window, which is the only answer left.
    nonisolated static func contentSize(
        opening: CGSize, chromeHeight: CGFloat, visibleHeight: CGFloat, floor: CGFloat
    ) -> CGSize {
        let room = max(floor, visibleHeight - chromeHeight)
        return CGSize(width: opening.width, height: min(opening.height, room))
    }

    /// The content size to stand at after a tab change: the clamped target where the window is
    /// smaller than it, and whatever the person has made it wherever they have made it larger.
    ///
    /// Only ever grows. Stepping onto a taller tab may not clip its pane, and stepping back
    /// onto a shorter one may not take away a size somebody chose.
    nonisolated static func grown(current: CGSize, toward target: CGSize) -> CGSize {
        CGSize(
            width: max(current.width, target.width),
            height: max(current.height, target.height))
    }

    /// The same frame moved until it lies inside the display's visible area.
    ///
    /// A window grows from a corner, so one that just grew is taller than it was without having
    /// moved, and its far edge can be off the screen — `constrainFrameRect` puts the title bar
    /// back under the menu bar and says nothing about the bottom, which is where a grown
    /// Settings window actually goes. A frame larger than the display keeps its top-left corner
    /// on screen and hangs off the far edge, since a title bar nobody can reach is worse than a
    /// bottom row nobody can see.
    nonisolated static func placed(_ frame: CGRect, inside visible: CGRect) -> CGRect {
        CGRect(
            x: start(frame.minX, length: frame.width, low: visible.minX, high: visible.maxX),
            y: start(frame.minY, length: frame.height, low: visible.minY, high: visible.maxY),
            width: frame.width, height: frame.height)
    }

    /// One axis of `placed`: the furthest a frame of this length may start and still end inside,
    /// which is where a frame too long for the axis is put.
    private nonisolated static func start(
        _ origin: CGFloat, length: CGFloat, low: CGFloat, high: CGFloat
    ) -> CGFloat {
        let last = high - length
        guard last > low else { return last }
        return min(max(origin, low), last)
    }
}
