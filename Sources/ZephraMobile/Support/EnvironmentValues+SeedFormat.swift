import SwiftUI
import ZephraCore

extension EnvironmentValues {
    /// How every seed on this phone is spelled: the capsule's chip and the sheet a seed is
    /// typed into both read this one value, and the composition root sets it from the Settings
    /// tab's preference through `SeedFormatPreference`, so no view below the root binds the key
    /// itself.
    ///
    /// A nine-line copy of the Mac's own `@Entry` rather than a shared one: the value is
    /// `ZephraCore`'s `SeedFormat` either way, and an environment key is per app.
    @Entry var seedFormat: SeedFormat = MobileSettings.initialSeedFormat
}
