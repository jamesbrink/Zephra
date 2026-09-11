import SwiftUI
import ZephraCore

/// Puts the General tab's seed spelling into the environment as `\.seedFormat`.
///
/// A modifier rather than a property on the root view, because `RootView` is at its three
/// stored properties and the preference is read once for the whole window; the `@AppStorage`
/// here is what makes the chip and the inspectors change as the picker in Settings moves.
struct SeedFormatPreference: ViewModifier {
    @AppStorage(AppSettings.seedFormat) private var format = AppSettings.initialSeedFormat

    func body(content: Content) -> some View {
        content.environment(\.seedFormat, format)
    }
}
