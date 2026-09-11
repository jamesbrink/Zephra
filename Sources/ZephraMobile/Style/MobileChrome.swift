import SwiftUI

/// The handful of measurements that are the phone's alone.
///
/// Everything a radius, a hairline or a wash could be comes from `ZephraStyle`, so the two
/// apps are drawn from one set of numbers. What lives here is what has no counterpart on the
/// Mac: the room a phone's tab bar takes away, and the margin down either side of a surface.
enum MobileChrome {
    /// The clear space a scrolling surface leaves under its last row, so the tab bar never
    /// sits on top of something that can be pressed.
    static let tabBarInset: CGFloat = 64
    /// The margin down either side of a surface. One number, so every screen's content lines
    /// up with every other screen's.
    static let sideMargin: CGFloat = 16
    /// The gap between stacked blocks of content on a surface.
    static let blockSpacing: CGFloat = 20

    /// How dark the backing behind the viewer's controls is, over whatever picture is under
    /// them. One number, because the close button and the action bar are the same idea and two
    /// numbers for it is two things to keep in step. The Mac has no counterpart: its viewer
    /// puts its controls beside the picture rather than on top of it.
    static let viewerChromeOpacity: Double = 0.45
    /// The black between two pictures as the viewer pages, so a swipe reads as one picture
    /// leaving and the next arriving rather than one wide strip sliding by. Photos' gap.
    static let viewerPageGap: CGFloat = 24
    /// How far down a picture is pulled before letting go closes the viewer. Short of it the
    /// picture springs back; the pull's dimming and shrinking are measured against it too.
    static let viewerDismissDistance: CGFloat = 160
}
