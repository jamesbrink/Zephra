import Foundation

/// The three tabs of the Settings window, and how tall each one stands.
///
/// One height per tab rather than one for the window, because the tabs are nothing alike:
/// General is three rows and Performance is a page. A window sized for the longest left the
/// shortest with two thirds of itself empty, which on the Mac reads as a broken layout rather
/// than as room. The heights are hand-measured, so a section added to a tab means a new
/// figure here; Models, whose list is the disk's and scrolls on its own, takes the height a
/// page of it wants.
///
/// `openingHeight` is only where the window opens, not the least it will shrink to — those used
/// to be the same number, and on a 13-inch MacBook Air M1, still supported by Sequoia, that
/// broke: 900 logical points tall less the 24-point menu bar is 876 usable, and Performance's
/// 820 of content plus the window's own 88 points of chrome (32 title bar, 56 tab-strip
/// toolbar, taller than the main window's 52 because it carries the tab icons) is 908 — over by
/// 32 points before Larger Text is even considered. So the floor is `minimumHeight`, one number
/// for all three tabs, well clear of that Mac; the window opens at each tab's own height when
/// the display has room for it, and a person who has made it taller keeps that size when they
/// step between tabs.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case performance
    case models

    var id: String { rawValue }

    /// The tab's name, which the Settings window also takes as its title.
    var title: String {
        switch self {
        case .general: "General"
        case .performance: "Performance"
        case .models: "Models"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .performance: "speedometer"
        case .models: "shippingbox"
        }
    }

    /// How wide the window opens, and the least it will narrow to — width has no equivalent of
    /// the height problem below, so one number still does both jobs. One width for all three,
    /// since every tab is a form of the same rows.
    static let openingWidth: CGFloat = 520

    /// The content size this tab opens at, when the display has room for it — see
    /// `minimumHeight` for what the window may be shrunk to instead.
    var openingSize: CGSize { CGSize(width: Self.openingWidth, height: openingHeight) }

    /// How tall the tab's content stands, in points, under the tab strip: where the window
    /// opens on this tab.
    ///
    /// Measured from the tabs as built: General is the appearance picker, the images folder
    /// row, and the seed toggle, the seed spelling picker with its caption and the
    /// notification toggle, with a heading each; Performance is the warm-up toggle, the
    /// four-row GPU memory group, the tiling picker and the live readout, all of which must
    /// be on screen at once, since a page that scrolls hides the very reading it is there to
    /// show; Models scrolls, so its height is what the longest Settings pane on the Mac
    /// usually takes, which is what the window was before.
    var openingHeight: CGFloat {
        switch self {
        case .general: 420
        case .performance: 820
        case .models: 620
        }
    }

    /// The least the window's content may be dragged to, whichever tab is showing. One number
    /// rather than one per tab, because this is a question about the window, not about any
    /// tab's own layout — a tab shorter than this simply sits with room beneath it, and
    /// Performance, the one tab that must not scroll at its full height, is free to scroll once
    /// dragged this small rather than being unable to shrink at all.
    ///
    /// 400 clears a 13-inch MacBook Air M1 (876 usable points, menu bar removed) with the
    /// window's 88 points of chrome added back — 488 against 876, more than the 24-point margin
    /// the M2/M3 Air would have gotten from Performance's own 820. AppKit clamps a window to the
    /// screen's visible frame on open, and it can only do that when the minimum it is holding to
    /// actually fits; pinning the floor at 820 is what made that clamp fail on the smallest
    /// Mac Sequoia still runs on.
    static let minimumHeight: CGFloat = 400
}
