import SwiftUI
import Testing
import ZephraCore

@testable import ZephraMobile

/// How a seed is spelled on the phone, which is the Settings tab's choice and the Mac's own
/// two spellings — not a hard-coded hex the phone could not change.
@Suite("The phone spells a seed the way Settings says")
struct SeedFormatOnThePhoneTests {
    @Test("Nothing chosen is the short hex label, as on the Mac")
    func startsAtHex() {
        #expect(EnvironmentValues().seedFormat == .hex)
        #expect(MobileSettings.initialSeedFormat == .hex)
    }

    @Test("Each spelling says what the field takes first")
    func footerLeadsWithTheSpellingInForce() {
        let hex = SeedEntrySheet.footer(for: .hex)
        let decimal = SeedEntrySheet.footer(for: .decimal)
        #expect(hex.contains("eight characters"))
        #expect(decimal.contains("0x"))
        #expect(hex != decimal)
    }

    @Test("Either spelling opens the field on the whole seed, never on the label")
    func theFieldOpensOnTheWholeSeed() {
        let seed: UInt64 = 0x7A3F_9C2E_1B0D_4F61
        #expect(SeedEntry.parse(SeedFormat.hex.exactText(seed)) == seed)
        #expect(SeedEntry.parse(SeedFormat.decimal.exactText(seed)) == seed)
    }
}
