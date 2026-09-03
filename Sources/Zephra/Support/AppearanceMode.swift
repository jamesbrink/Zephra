import AppKit

/// Whether the app follows the Mac's appearance or fixes its own.
///
/// System is the default and means "no opinion": the app is drawn from system materials and
/// colour sets with a dark variant, so it needs no override to look right either way. The
/// other two are for the person who wants the canvas dark in a light room, or the reverse.
enum AppearanceMode: String, CaseIterable, Identifiable {
    /// Whatever the Mac is set to, and changing with it.
    case system
    /// Light, whatever the Mac is set to.
    case light
    /// Dark, whatever the Mac is set to.
    case dark

    var id: String { rawValue }

    /// How the setting reads in the picker.
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What to hand `NSApplication.appearance`: nil clears the override, so every window goes
    /// back to following the Mac.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
