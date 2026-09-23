import Foundation
import ZephraCore

/// How each of the inspector's lines is spelled: the rules for no answer at all, seconds against
/// minutes, a per-step pace, a clip's length and where it carried on from.
extension ImageFacts {
    /// A strength worth showing: not one that was never recorded, and not the 1 that means the
    /// generation had no distance to travel from its picture.
    static func reportable(_ strength: Double?) -> Double? {
        guard let strength, strength != 1 else { return nil }
        return strength
    }

    /// The strength as the slider spells it, to two decimals.
    static func strengthLabel(_ strength: Double) -> String {
        strength.formatted(.number.precision(.fractionLength(2)))
    }

    /// "2 s, 49 frames at 24 fps", the seconds to one decimal only when a ladder of eight
    /// frames does not land on a whole one.
    static func lengthLabel(frames: Int, rate: Double, sound: Bool = false) -> String {
        let seconds = DurationLabel.text(seconds: Double(frames) / rate, fraction: true)
        let length = String(format: "%@, %d frames at %.0f fps", seconds, frames, rate)
        return sound ? "\(length), with sound" : length
    }

    /// What a clip carried on says about it: the source's file name and how many of its
    /// frames were held at the join.
    static func continuedLabel(from origin: String, held: Int) -> String {
        held == 1
            ? "\(origin), from its last frame"
            : "\(origin), \(held) frames held"
    }

    /// How long a generation took, with what that came to per step.
    ///
    /// The whole is a `DurationLabel` — "1 min 7 s" rather than "66.7 s" — with a decimal under
    /// a minute, since a four-step run is over in a few seconds and "7 s" for 6.9 would be a
    /// rounding the per-step figure beside it contradicts. That per-step figure stays in
    /// seconds throughout: it is a pace, and what a benchmark and a model's page both quote.
    public static func tookLabel(seconds: Double, steps: Int) -> String {
        guard seconds > 0 else { return unknown }
        let whole = DurationLabel.text(seconds: seconds, fraction: true)
        guard steps > 0 else { return whole }
        return "\(whole) \(separator) \(number(seconds / Double(steps))) s/step"
    }

    /// How many steps ran. None at all is not a generation but an upscale of a picture Zephra
    /// did not make, and "0" would read as a number that was once true.
    static func stepsLabel(_ steps: Int?) -> String {
        guard let steps, steps > 0 else { return unknown }
        return String(steps)
    }

    /// The seed, for the same reason: no seed was drawn when no denoising loop ran.
    static func seedLabel(_ seed: UInt64?, as format: SeedFormat) -> String {
        guard let seed, seed > 0 else { return unknown }
        return format.label(seed)
    }

    /// A middle dot, the separator the rest of the interface uses between facts.
    public static let separator = "\u{00B7}"
    /// What is shown where there is no answer.
    public static let unknown = "\u{2014}"
    /// What is shown for an image that has not reached the disk.
    public static let notSaved = "Not saved yet"

    static func label(_ size: ImageSize) -> String {
        "\(size.width) \u{00D7} \(size.height)"
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
