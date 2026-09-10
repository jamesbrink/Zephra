import Foundation

/// Where one stage's steps sit in a run reported as a single count: a two-stage run is eight
/// steps and then three, and the interface counts to eleven.
struct LTX2StepRange: Hashable, Sendable {
    /// The one-based number the stage's first step is reported as.
    let first: Int
    /// The run's step count as a whole.
    let total: Int
}
