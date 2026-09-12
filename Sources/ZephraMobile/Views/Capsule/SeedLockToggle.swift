import SwiftUI

/// The lock beside the seed: closed, every press keeps this seed; open, every press picks a
/// fresh one.
///
/// The Mac's `SeedControl` wears the same lock over the same preference, and it is the one
/// control in the capsule that changes a setting rather than the request. It belongs here
/// rather than only in Settings because the moment somebody wants a seed held is the moment
/// they are looking at it — a picture they want another try at with one thing changed.
struct SeedLockToggle: View {
    @AppStorage(MobileSettings.randomizeSeedEachRun) private var randomize =
        MobileSettings.initialRandomizeSeedEachRun

    var body: some View {
        Toggle(isOn: Binding(get: { !randomize }, set: { randomize = !$0 })) {
            Image(systemName: randomize ? "lock.open" : "lock.fill")
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .accessibilityLabel("Keep seed")
        .accessibilityHint(Self.hint(randomizing: randomize))
    }

    /// What the lock says it will do, in the Mac's own words for it.
    static func hint(randomizing: Bool) -> String {
        randomizing
            ? "Each run picks a new seed. Tap to keep this one."
            : "Keeping this seed for every run."
    }
}
