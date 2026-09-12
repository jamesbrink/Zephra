import SwiftUI

/// Whether every press of Generate picks a fresh seed, or keeps repeating the last one.
///
/// Only the switch: nothing reads this key yet but `GenerateButton`, which is Item 3's wiring.
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
