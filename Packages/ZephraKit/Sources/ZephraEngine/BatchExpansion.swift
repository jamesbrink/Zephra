import ZephraCore

/// Turns one set of settings into the several a batch runs.
///
/// A pure function with the randomness handed in, so the interesting part — that the first
/// image is exactly what a run of one would have produced, and only the ones after it get new
/// seeds — is testable without a backend or a clock. Pressing Generate with a batch of four
/// should never change what the seed in the field means.
public enum BatchExpansion {
    /// `count` copies of `settings`: the first as it stands, the rest on fresh seeds from `seed`.
    public static func expand(
        _ settings: GenerationSettings,
        count: Int,
        seed: () -> UInt64
    ) -> [GenerationSettings] {
        guard count > 0 else { return [] }
        var expanded = [settings]
        for _ in 1..<max(count, 1) {
            var copy = settings
            copy.seed = seed()
            expanded.append(copy)
        }
        return expanded
    }
}
