import Foundation

/// A clip longer than one pass, as the passes that make it.
///
/// A family's transformer and decoder take at most `frameBounds.upperBound` frames at once; a
/// longer clip is made as a chain of segments, each carried on from the last frames of the one
/// before (`ClipContinuation`), and joined at the end. Every segment after the first holds
/// `defaultContinuationFrames` frames it did not make, so it adds `length - context` new
/// frames; the plan spends whole passes first and the remainder last, on the model's ladder
/// throughout, so the joined clip is exactly the count asked for.
public enum ChainPlan {
    /// The most passes one clip may chain: four is twenty seconds on either family, past
    /// which a run is a coffee and a stitch is a file worth a script.
    public static let maxPasses = 4

    /// The longest clip `capabilities` makes, chained: one full pass plus the new frames of
    /// three more, or the single pass on a model that cannot continue one.
    public static func maxFrames(_ capabilities: ModelCapabilities) -> Int {
        let pass = capabilities.frameBounds.upperBound
        guard capabilities.supportsContinuation else { return pass }
        return pass + (maxPasses - 1) * (pass - capabilities.defaultContinuationFrames)
    }

    /// The segment lengths that make a clip of `frames`: `[frames]` when one pass does, else a
    /// full pass followed by passes of `context + new` until the count is met. `frames` is
    /// snapped down the ladder and bounded by `maxFrames` first, so a model that cannot
    /// continue answers one bounded pass, as `clamp` would.
    public static func segments(frames: Int, capabilities: ModelCapabilities) -> [Int] {
        let pass = capabilities.frameBounds.upperBound
        let alignment = capabilities.frameAlignment
        let total = snapped(min(max(frames, capabilities.frameBounds.lowerBound), maxFrames(capabilities)), alignment: alignment)
        guard total > pass, capabilities.supportsContinuation else { return [min(total, pass)] }
        let context = capabilities.defaultContinuationFrames
        var lengths = [pass]
        var remaining = total - pass
        while remaining > 0 {
            let fresh = min(pass - context, remaining)
            lengths.append(fresh + context)
            remaining -= fresh
        }
        return lengths
    }

    /// How many frames a chain of `segments` makes once joined, the held frames counted once.
    public static func joinedFrames(_ segments: [Int], context: Int) -> Int {
        guard let first = segments.first else { return 0 }
        return first + segments.dropFirst().reduce(0) { $0 + $1 - context }
    }

    private static func snapped(_ frames: Int, alignment: Int) -> Int {
        1 + ((frames - 1) / alignment) * alignment
    }
}
