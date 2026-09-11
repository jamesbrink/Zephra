import SwiftUI

/// The four surfaces the phone has, which is the whole of its navigation.
///
/// An enum rather than four literals in the `TabView`, so the frozen preview states can open
/// the app on one of them and the tests can name one.
enum MobileTab: String, CaseIterable, Identifiable {
    /// What the Mac is making right now, and the controls that ask it for more.
    case canvas
    /// Today's runs, as the Mac's own sidebar groups them.
    case today
    /// The Mac's whole library.
    case library
    /// The Mac this phone is paired to, and what to do about it.
    case settings

    var id: String { rawValue }

    /// The word on the tab.
    var title: String {
        switch self {
        case .canvas: "Canvas"
        case .today: "Today"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    /// The SF Symbol on the tab.
    var symbol: String {
        switch self {
        case .canvas: "photo.on.rectangle.angled"
        case .today: "clock"
        case .library: "square.grid.2x2"
        case .settings: "gearshape"
        }
    }
}
