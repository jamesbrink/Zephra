import SwiftUI

/// Whether an app follows the system's appearance or fixes its own.
///
/// System is the default and means "no opinion": both apps are drawn from system materials and
/// colour sets with a dark variant, so neither needs an override to look right either way. The
/// other two are for the person who wants the canvas dark in a light room, or the reverse. It
/// lives here rather than in either app's own `Support/`, because both apps read one preference
/// and apply it their own way — the Mac sets `NSApplication.appearance` so Settings, menus and
/// alerts all follow; the phone's one `WindowGroup` needs nothing but `preferredColorScheme`.
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    /// Whatever the system is set to, and changing with it.
    case system
    /// Light, whatever the system is set to.
    case light
    /// Dark, whatever the system is set to.
    case dark

    public var id: String { rawValue }

    /// How the setting reads in the picker.
    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What to hand `preferredColorScheme`: nil leaves the choice to the system, exactly as nil
    /// clears the Mac's `NSAppearance` override.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
