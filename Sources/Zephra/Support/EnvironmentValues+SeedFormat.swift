import SwiftUI
import ZephraCore

extension EnvironmentValues {
    /// How every seed on screen is spelled: the chip, the inspectors' Seed row, the running
    /// run's column and the entry popover all read this one value, and the composition root
    /// sets it from the General tab's preference through `SeedFormatPreference`, so no view
    /// below the root binds the key itself.
    @Entry var seedFormat: SeedFormat = AppSettings.initialSeedFormat
}
