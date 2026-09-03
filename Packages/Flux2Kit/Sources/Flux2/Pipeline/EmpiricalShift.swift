import Foundation

/// How far the noise schedule is bent towards its noisy end, for FLUX.2.
///
/// A big image has more tokens to agree with each other, so it needs longer at high noise to
/// settle on a composition. Qwen-Image draws a straight line through two published points;
/// FLUX.2's pipeline instead carries two fitted lines, one for ten steps and one for two
/// hundred, and interpolates between them by step count. The constants are the reference's, to
/// the digit, and they are not in any config file: the scheduler's `base_shift` and `max_shift`
/// describe a schedule no klein image is made with.
public enum EmpiricalShift {
    /// The shift exponent for an image of `imageSequenceLength` tokens made in `steps` steps.
    ///
    /// Only the image being made counts. A reference image handed in for editing adds tokens
    /// to the sequence but not to this.
    public static func mu(imageSequenceLength: Int, steps: Int) -> Double {
        let tokens = Double(imageSequenceLength)
        let (a1, b1) = (8.73809524e-05, 1.89833333)
        let (a2, b2) = (0.00016927, 0.45666666)

        let atTwoHundred = a2 * tokens + b2
        if imageSequenceLength > 4300 {
            return atTwoHundred
        }
        let atTen = a1 * tokens + b1
        let slope = (atTwoHundred - atTen) / 190
        let intercept = atTwoHundred - 200 * slope
        return slope * Double(steps) + intercept
    }
}
