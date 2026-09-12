import AppKit
import SwiftUI
import ZephraStyle

/// Puts the stored appearance preference onto the application, once at launch and again
/// whenever the preference moves.
///
/// Set on `NSApp` rather than as a `preferredColorScheme`, because a colour scheme on a scene
/// covers that scene's window alone; the Settings window, the model menu, and every alert would
/// stay on the Mac's appearance. The application's appearance covers all of them at once.
///
/// One `@AppStorage`, held here and nowhere else that applies it: the picker in Settings binds
/// the same key, and a change made there reaches this modifier through `UserDefaults`, so
/// there is exactly one place the preference becomes an appearance.
struct AppearanceApplier: ViewModifier {
    @AppStorage(AppSettings.appearance) private var mode = AppSettings.initialAppearance

    func body(content: Content) -> some View {
        content.onChange(of: mode, initial: true) { _, mode in
            NSApp.appearance = mode.nsAppearance
        }
    }
}

extension View {
    /// Applies the stored appearance preference to the whole application.
    func applyingAppearancePreference() -> some View {
        modifier(AppearanceApplier())
    }
}
