import Foundation
import SwiftUI
import Testing
import ZephraCore
import ZephraStyle

@testable import ZephraMobile

/// The phone's preference layer: every key starts where the Mac starts it, a frozen launch —
/// every screenshot and every hosted test among them — never touches a person's own
/// preferences, and the two rows that spell things two ways spell them correctly.
@Suite("Every phone preference starts at the Mac's own default")
struct MobileSettingsTests {
    @Test("Appearance, seed spelling and the seed rule start where the Mac starts them")
    func startingValues() {
        #expect(MobileSettings.initialAppearance == .system)
        #expect(MobileSettings.initialSeedFormat == .hex)
        #expect(MobileSettings.initialRandomizeSeedEachRun == true)
        #expect(MobileSettings.flag(MobileSettings.randomizeSeedEachRun) == true)
    }

    @Test("A frozen launch reads a throwaway suite, never a person's own preferences")
    func frozenLaunchIsThrowaway() {
        // The `ZephraMobile` scheme always launches ZephraMobileTests with
        // ZEPHRA_PREVIEW_STATE set, exactly as the Mac's own test host does; see
        // `MobilePreview`. So every hosted test, this one included, runs frozen.
        #expect(MobilePreview.state != nil)
        #expect(MobileSettings.store !== UserDefaults.standard)
    }

    @Test("System has no opinion of its own; light and dark are fixed")
    func systemDefersToTheDevice() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test("The seed caption spells one seed both ways")
    func captionSpellsBothWays() {
        let seed: UInt64 = 0x7A3F_9C2E_1B0D_4F61
        let caption = SeedFormatRow.caption(seed)
        #expect(caption.contains(SeedFormat.hex.label(seed)))
        #expect(caption.contains(SeedFormat.decimal.label(seed)))
    }
}
