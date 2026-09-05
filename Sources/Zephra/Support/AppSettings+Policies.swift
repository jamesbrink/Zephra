import Foundation
import ZephraCore

/// The two memory policies built from stored preferences, for the composition root and the
/// Performance tab, which have to answer the same question the pickers do outside a view.
extension AppSettings {
    /// How the stored preference and this machine's memory budget decide the VAE tile, for
    /// the composition root, which has to answer the question outside a picker.
    static func tilingPolicy(budget: MemoryBudget) -> VAETilingPolicy {
        let stored = UserDefaults.standard.string(forKey: vaeTiling)
        return VAETilingPolicy(
            mode: stored.flatMap(VAETilingMode.init(rawValue:)) ?? initialVAETiling,
            budget: budget
        )
    }

    /// How the stored preference and this machine's memory budget decide where a model's
    /// weights live, for the composition root, which sets it on the store before bootstrap.
    /// `ZEPHRA_WEIGHT_RESIDENCY=streamed|resident` overrides the preference for one launch,
    /// the way `ZEPHRA_VAE_TILE` does for the tile.
    static func residencyPolicy(budget: MemoryBudget) -> WeightResidencyPolicy {
        let stored = UserDefaults.standard.string(forKey: weightResidency)
        return residencyPolicy(
            mode: stored.flatMap(WeightResidencyMode.init(rawValue:)) ?? initialWeightResidency,
            budget: budget)
    }

    /// The policy for a chosen mode, with the launch's environment override applied, so the
    /// Performance tab's picker and the composition root agree while the override is in force.
    static func residencyPolicy(mode: WeightResidencyMode, budget: MemoryBudget) -> WeightResidencyPolicy {
        let overridden: WeightResidencyMode? =
            switch ProcessInfo.processInfo.environment["ZEPHRA_WEIGHT_RESIDENCY"] {
            case "streamed": .always
            case "resident": .never
            default: nil
            }
        return WeightResidencyPolicy(mode: overridden ?? mode, budget: budget)
    }
}
