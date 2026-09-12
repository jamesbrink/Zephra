import AppKit
import ZephraStyle

extension AppearanceMode {
    /// What to hand `NSApplication.appearance`: nil clears the override, so every window goes
    /// back to following the Mac. AppKit stays on this side of `ZephraStyle`, which the phone
    /// links too and which `make lint-layers` bans it from.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
