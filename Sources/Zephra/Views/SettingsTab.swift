import Foundation

/// The four tabs of the Settings window, and how tall each one stands.
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
/// content plus the window's own 88 points of chrome (32 title bar, 56 tab-strip
/// toolbar, taller than the main window's 52 because it carries the tab icons) is 908 — over by
/// 32 points before Larger Text is even considered. So the floor is `minimumHeight`, one number
/// for all four tabs, well clear of that Mac; the window opens at each tab's own height when
/// the display has room for it, and a person who has made it taller keeps that size when they
/// step between tabs.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case performance
    case models
    case companion

    var id: String { rawValue }

    /// The tab's name, which the Settings window also takes as its title.
    var title: String {
        switch self {
        case .general: "General"
        case .performance: "Performance"
        case .models: "Models"
        case .companion: "Companion"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .performance: "speedometer"
        case .models: "shippingbox"
        case .companion: "iphone"
        }
    }

    /// How wide the window opens, and the least it will narrow to — width has no equivalent of
    /// the height problem below, so one number still does both jobs. One width for all four,
    /// since every tab is a form of the same rows.
    static let openingWidth: CGFloat = 520

    /// The content size this tab opens at, when the display has room for it — see
    /// `minimumHeight` for what the window may be shrunk to instead.
    var openingSize: CGSize { CGSize(width: Self.openingWidth, height: openingHeight) }

    /// How tall the tab's content stands, in points, under the tab strip: where the window
    /// opens on this tab.
    ///
    /// Measured from the tabs as built: General is the appearance picker, the images folder
    /// row, the seed toggle, the seed spelling picker with its caption and the two-line
    /// notification toggle, and the update toggle, with a heading each; Performance is the loading section, the
    /// warm-up toggle, the four-row GPU memory group, the tiling picker and the live readout,
    /// which wants to be on screen at once, since a page that scrolls hides the very reading
    /// it is there to show; Models scrolls, so its height is what the longest Settings pane on the Mac
    /// usually takes, which is what the window was before; Companion is the two toggles, the
    /// code and the list of paired devices, with room for the code at the size a phone's camera
    /// reads across a desk.
    ///
    /// General's figure was re-measured with `make screenshot WINDOW=General` when the update
    /// section arrived: 420 and 480 both left the Updates toggle below the sill, and 560 is
    /// where the tab shows its last row with a margin under it.
    var openingHeight: CGFloat {
        switch self {
        case .general: 560
        case .performance: 930
        case .models: 620
        case .companion: 600
        }
    }

    /// The least the window's content may be dragged to, whichever tab is showing. One number
    /// rather than one per tab, because this is a question about the window, not about any
    /// tab's own layout — a tab shorter than this simply sits with room beneath it, and
    /// Performance, the one tab that must not scroll at its full height, is free to scroll once
    /// dragged this small rather than being unable to shrink at all.
    ///
    /// 400 clears a 13-inch MacBook Air M1 (876 usable points, menu bar removed) with the
    /// window's 88 points of chrome added back — 488 against 876, more than the margin
    /// the M2/M3 Air would once have gotten from Performance's own 820. Performance now stands
    /// 930 and so opens clamped and scrolling on a 13-inch Air, which is exactly what this
    /// floor exists for: the live readout stays at the bottom, under a Loading section added
    /// at the top, so what is pushed off on that Mac is not the reading the tab is there for. AppKit clamps a window to the
    /// screen's visible frame on open, and it can only do that when the minimum it is holding to
    /// actually fits; pinning the floor at 820 is what made that clamp fail on the smallest
    /// Mac Sequoia still runs on.
    static let minimumHeight: CGFloat = 400
}
