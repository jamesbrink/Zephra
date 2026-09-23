import Foundation
import ZephraCore

/// The one line the guidance control says under itself: that guidance above 1 needs a negative
/// prompt to push away from.
///
/// Classifier-free guidance is the gap between the prompt's prediction and the negative
/// prompt's, and a model that reads a negative prompt runs that second forward only when there
/// is one — `diffusers` does exactly this, and the port is faithful to it. So guidance moved off
/// 1 with the negative field empty changes nothing, and a slider that moves while the picture
/// does not reads as a broken control rather than as a missing input. Silent on a model without
/// a negative prompt, where guidance means whatever that model makes of it.
enum GuidanceNote {
    /// The sentence the control shows.
    static let needsNegativePrompt = "Guidance needs something to avoid."

    /// The note for `settings` on a model with `capabilities`, or nil when there is nothing to
    /// say: guidance at 1 or under, a negative prompt with something in it, or a model where
    /// guidance is not a choice or reads no negative prompt.
    static func text(for settings: GenerationSettings, capabilities: ModelCapabilities) -> String? {
        guard capabilities.adjustsGuidance, capabilities.supportsNegativePrompt,
              settings.guidance > 1
        else { return nil }
        let negative = settings.negativePrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return negative.isEmpty ? needsNegativePrompt : nil
    }
}
