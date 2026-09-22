import Foundation

/// How far the noise schedule is bent towards its noisy end, as a function of image size.
///
/// A big image has more tokens to agree with each other, so it needs longer at high noise to
/// settle on a composition. The published constants say where the line runs: `baseShift` at
/// `baseImageSeqLen` tokens, `maxShift` at `maxImageSeqLen`, linear in between.
///
/// **Nothing clamps.** The reference's `calculate_shift` is the bare line, so an image past
/// `maxImageSeqLen` — 2048 square is 16384 tokens against a ceiling of 8192 — extrapolates
/// beyond `maxShift` rather than stopping at it. Clamping would be the reasonable thing and
/// would give a different picture from the same seed, so it is not done.
public enum QwenImage21DynamicShift {
    /// The shift exponent for an image of `imageSequenceLength` tokens.
    public static func mu(
        imageSequenceLength: Int,
        configuration: QwenImage21SchedulerConfiguration
    ) -> Double {
        let slope =
            (configuration.maxShift - configuration.baseShift)
            / Double(configuration.maxImageSeqLen - configuration.baseImageSeqLen)
        let intercept = configuration.baseShift - slope * Double(configuration.baseImageSeqLen)
        return Double(imageSequenceLength) * slope + intercept
    }
}
