import Foundation
import ZephraCore
import ZephraStyle

/// The phone's one list of preference keys, mirroring `AppSettings` on the Mac: bind with
/// `@AppStorage` at the row, read elsewhere through `flag(_:)`.
enum MobileSettings {
    /// Where every preference below is read and written.
    ///
    /// `.standard` for an ordinary launch. Under a frozen preview state — every screenshot and
    /// every hosted test, which the `ZephraMobile` scheme always launches with
    /// `ZEPHRA_PREVIEW_STATE` set — a suite of its own, with its persistent domain removed
    /// before anything reads it, so a run never inherits what an earlier one left behind. The
    /// same reason `AppSettings.store` redirects under the Mac's `FreshStart`.
    static let store: UserDefaults = {
        guard MobilePreview.state != nil,
            let suite = UserDefaults(suiteName: previewSuite)
        else { return .standard }
        suite.removePersistentDomain(forName: previewSuite)
        return suite
    }()

    /// The domain a frozen launch's preferences live in, never a person's own.
    private static let previewSuite = "io.zephra.ZephraMobile.preview"

    /// Whether the phone follows the Mac's appearance or fixes its own, as an `AppearanceMode`
    /// raw value.
    static let galleryColumns = "galleryColumns"
    static let appearance = "appearance"
    /// How a seed is written wherever one is shown, as a `SeedFormat` raw value.
    static let seedFormat = "seedFormat"
    /// Whether every run picks a fresh seed instead of repeating the last one.
    static let randomizeSeedEachRun = "randomizeSeedEachRun"

    // Starting values, matching the defaults written at each `@AppStorage` site, and the
    // Mac's own defaults for the two preferences both apps share.

    /// The system's own appearance, until the user picks one.
    static let initialAppearance = AppearanceMode.system
    /// The short hex label: eight characters that fit a chip and tell two seeds apart.
    static let initialSeedFormat = SeedFormat.hex
    /// A fresh seed each run is the friendlier default; a fixed seed is the deliberate choice.
    static let initialRandomizeSeedEachRun = true

    /// A stored flag as it stands right now, for the code that has to read one outside a view
    /// and so cannot use `@AppStorage`. An unset key falls back to the same starting value the
    /// rows use, so a preference means one thing everywhere.
    static func flag(_ key: String) -> Bool {
        store.object(forKey: key) as? Bool ?? initialValue(of: key)
    }

    private static func initialValue(of key: String) -> Bool {
        switch key {
        case randomizeSeedEachRun: initialRandomizeSeedEachRun
        default: false
        }
    }
}
