import SwiftUI

/// Whether every press of Generate picks a fresh seed, or keeps repeating the last one.
///
/// What reads it is the press itself (`PromptDraft.submission(clampedBy:randomizingSeed:)`,
/// from `GenerateButton`), and `SeedLockToggle` in the capsule writes the same key, so the lock
/// beside the seed and this switch are one preference shown twice.
struct RandomizeSeedRow: View {
    @AppStorage(MobileSettings.randomizeSeedEachRun) private var randomize =
        MobileSettings.initialRandomizeSeedEachRun

    var body: some View {
        Toggle("Pick a new seed for every run", isOn: $randomize)
    }
}

#Preview("Randomize seed") {
    Form { RandomizeSeedRow() }
}
