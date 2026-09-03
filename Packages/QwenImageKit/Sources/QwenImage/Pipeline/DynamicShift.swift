import Foundation

/// How far the noise schedule is bent towards its noisy end, as a function of image size.
///
/// A big image has more tokens to agree with each other, so it needs longer at high noise to
/// settle on a composition. The published constants say where the line runs: `baseShift` at
/// `baseImageSeqLen` tokens, `maxShift` at `maxImageSeqLen`, linear in between and extrapolated
/// outside.
public enum DynamicShift {
    /// The shift exponent for an image of `imageSequenceLength` tokens.
    public static func mu(
        imageSequenceLength: Int,
        configuration: QwenImageSchedulerConfiguration
    ) -> Double {
        let slope =
            (configuration.maxShift - configuration.baseShift)
            / Double(configuration.maxImageSeqLen - configuration.baseImageSeqLen)
        let intercept = configuration.baseShift - slope * Double(configuration.baseImageSeqLen)
        return Double(imageSequenceLength) * slope + intercept
    }
}
