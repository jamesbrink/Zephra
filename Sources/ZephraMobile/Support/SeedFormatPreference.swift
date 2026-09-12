import SwiftUI
import ZephraCore

/// Puts the Settings tab's seed spelling into the environment as `\.seedFormat`.
///
/// A modifier at the root rather than an `@AppStorage` at each seed, for the Mac's own reason
/// (`SeedFormatPreference` there): the preference is read once for the whole app, and the views
/// that draw a seed are already at their three stored properties. The `@AppStorage` here is
/// what makes the chip and the entry sheet change as the picker in Settings moves.
struct SeedFormatPreference: ViewModifier {
    @AppStorage(MobileSettings.seedFormat) private var format = MobileSettings.initialSeedFormat

    func body(content: Content) -> some View {
        content.environment(\.seedFormat, format)
    }
}
