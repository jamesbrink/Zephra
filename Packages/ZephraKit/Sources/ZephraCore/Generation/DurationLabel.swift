import Foundation

/// A span of seconds as a person reads it: "45 s", "1 min 20 s", "12 min", "1 hr 5 min".
///
/// One rule for every duration the interface shows — the countdown, Elapsed and Left, how
/// long a run took, a clip's length, the badge on a clip's thumbnail — because "~559 s left"
/// is a number to be divided rather than a time to be felt. The unit words are the short
/// forms the rest of the interface already uses ("s" beside "s/step"), and the precision
/// steps down as the span grows: seconds to one decimal only under a minute and only when
/// asked (a clip's length, where 0.4 s is a real answer), whole seconds up to ten minutes,
/// whole minutes up to an hour, and hours with minutes past that. A per-step pace is not a
/// duration and keeps its seconds; see `ImageFacts.tookLabel`.
public enum DurationLabel {
    /// The span written out. `fraction` allows one decimal under a minute when the seconds
    /// are not whole; without it they are rounded, which is what a countdown wants.
    public static func text(seconds: Double, fraction: Bool = false) -> String {
        let total = max(0, seconds)
        if total < 60 {
            if fraction, total.rounded() != total {
                return "\(total.formatted(.number.precision(.fractionLength(1)))) s"
            }
            return "\(Int(total.rounded())) s"
        }
        let whole = Int(total.rounded())
        if whole < 600 {
            let minutes = whole / 60, rest = whole % 60
            return rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s"
        }
        let minutes = Int((total / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}
