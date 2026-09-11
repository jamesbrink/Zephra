import SwiftUI

/// The handful of measurements that are the phone's alone.
///
/// Everything a radius, a hairline or a wash could be comes from `ZephraStyle`, so the two
/// apps are drawn from one set of numbers. What lives here is what has no counterpart on the
/// Mac: a sheet that rises from the bottom of a phone, and the room a tab bar takes away.
enum MobileChrome {
    /// How much of the screen the prompt sheet covers when it is up: enough for the prompt,
    /// the model and the size, and no more, so the picture behind it stays the subject.
    static let sheetHeight: CGFloat = 0.55
    /// The sheet at its smallest, showing the prompt's first line and the Generate button.
    static let sheetCollapsedHeight: CGFloat = 132

    /// The clear space a scrolling surface leaves under its last row, so the tab bar never
    /// sits on top of something that can be pressed.
    static let tabBarInset: CGFloat = 64
    /// The margin down either side of a surface. One number, so every screen's content lines
    /// up with every other screen's.
    static let sideMargin: CGFloat = 16
    /// The gap between stacked blocks of content on a surface.
    static let blockSpacing: CGFloat = 20
}
