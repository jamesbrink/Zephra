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
/// A height is where the window opens and the least it will shrink to, not what it is pinned
/// at: the window resizes, and a person who has made it taller keeps that size when they step
/// between tabs whose floors are shorter.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case performance
    case models
    case about

    var id: String { rawValue }

    /// The tab's name, which the Settings window also takes as its title.
    var title: String {
        switch self {
        case .general: "General"
        case .performance: "Performance"
        case .models: "Models"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .performance: "speedometer"
        case .models: "shippingbox"
        case .about: "info.circle"
        }
    }

    /// How wide the window opens, and the least it will narrow to. One width for all four,
    /// since every tab is a form of the same rows.
    static let openingWidth: CGFloat = 520

    /// The content size this tab opens at, which is also the smallest it may be dragged to.
    var openingSize: CGSize { CGSize(width: Self.openingWidth, height: openingHeight) }

    /// How tall the tab's content stands, in points, under the tab strip: where the window
    /// opens on this tab, and the floor it will not shrink past.
    ///
    /// Measured from the tabs as built: General is the appearance picker, the images folder
    /// row, and the seed toggle, the seed spelling picker with its caption and the
    /// notification toggle, with a heading each; Performance is the warm-up toggle, the
    /// four-row GPU memory group, the tiling picker and the live readout, all of which must
    /// be on screen at once, since a page that scrolls hides the very reading it is there to
    /// show; Models scrolls, so its height is what the longest Settings pane on the Mac
    /// usually takes, which is what the window was before; About is the icon, two short
    /// paragraphs, two buttons and the copyright.
    var openingHeight: CGFloat {
        switch self {
        case .general: 420
        case .performance: 820
        case .models: 620
        case .about: 300
        }
    }
}
