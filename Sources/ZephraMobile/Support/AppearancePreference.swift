import SwiftUI
import ZephraStyle

/// Applies the phone's stored appearance preference to the one window.
///
/// `preferredColorScheme` is enough here, unlike the Mac's `AppearanceApplier`, which sets
/// `NSApplication.appearance`: the phone has one `WindowGroup` and one scene, so a colour
/// scheme applied at the root covers everything drawn under it, alerts and sheets included.
struct AppearancePreference: ViewModifier {
    @AppStorage(MobileSettings.appearance) private var mode = MobileSettings.initialAppearance

    func body(content: Content) -> some View {
        content.preferredColorScheme(mode.colorScheme)
    }
}
