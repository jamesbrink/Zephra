import Foundation

/// The lengths a clip model's Duration menu offers, and how one of them reads.
///
/// Seconds rather than frames, because a person asks for a two-second clip and not a
/// forty-nine-frame one; the label shows both, so the number the record carries is not a
/// surprise. A length past one pass is a chain (`ChainPlan`), and the label says so.
///
/// It lives here rather than in either app's `DurationControl` because both apps draw this
/// menu and a phone offering a shorter list than the Mac is a rule spelled twice: the Mac
/// plans the chain either way, so the phone may ask for any length the Mac would run.
public enum ClipLength {
    /// The frame counts offered: the shortest clip the model makes, then one per whole second
    /// up to one pass — at 24 fps on a ladder of eight, 25, 49, 73, 97 and 121 frames for one
    /// to five seconds — and, on a model that carries a clip on, every five seconds past that
    /// up to `ChainPlan.maxFrames`, each made as a chain of passes.
    public static func choices(_ capabilities: ModelCapabilities) -> [Int] {
        let bounds = capabilities.frameBounds
        let alignment = Double(capabilities.frameAlignment)
        let longest = ChainPlan.maxFrames(capabilities)
        var frames: Set<Int> = [bounds.lowerBound]
        var seconds = 1
        while Double(seconds) * capabilities.frameRate <= Double(longest) + alignment / 2 {
            let rungs = ((Double(seconds) * capabilities.frameRate - 1) / alignment).rounded()
            let count = 1 + Int(rungs) * capabilities.frameAlignment
            if bounds.contains(count) || (count > bounds.upperBound && count <= longest && seconds % 5 == 0) {
                frames.insert(count)
            }
            seconds += 1
        }
        return frames.sorted()
    }

    /// How many passes a clip of `frames` takes on this model.
    public static func passes(of frames: Int, capabilities: ModelCapabilities) -> Int {
        ChainPlan.segments(frames: frames, capabilities: capabilities).count
    }

    /// One menu item, or the menu's own label: the length and, past one pass, how many passes
    /// make it.
    public static func label(frames: Int, capabilities: ModelCapabilities) -> String {
        label(
            frames: frames, rate: capabilities.frameRate,
            passes: passes(of: frames, capabilities: capabilities))
    }

    /// "2 s · 49 frames", with the seconds to one decimal only when they are not whole, and
    /// "· 2 passes" after it when the clip is longer than one.
    public static func label(frames: Int, rate: Double, passes: Int = 1) -> String {
        let length = "\(DurationLabel.text(seconds: Double(frames) / rate, fraction: true)) · \(frames) frames"
        return passes > 1 ? "\(length) · \(passes) passes" : length
    }
}
