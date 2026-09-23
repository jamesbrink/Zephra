import Foundation

/// The closure a backend hands its pipeline's `onPreview` hook, written once for every family.
///
/// A pipeline calls the hook after each step with the step, the step count, and a *way to make*
/// a frame. This decides whether to spend the decode — one `PreviewThrottle` per run, so a frame
/// is made at most every so often however fast the steps go by, and never more often than its
/// own cost allows — times the decode when it does, tells the throttle what it cost, and
/// reports the result as a `GenerationProgressEvent`. Three backends used to carry this
/// same closure each; the frame types differ, which is what the generic is for.
public enum PreviewFrameReporter {
    /// What a pipeline's preview hook looks like, over that pipeline's own frame type.
    public typealias Handler<Frame: PreviewFrame> = (
        _ step: Int, _ total: Int, _ frame: () throws -> Frame
    ) -> Void

    /// A hook throttled to `interval`, or nil when `interval` is nil, which is how frames are
    /// switched off: a pipeline handed no hook skips the check entirely rather than asking an
    /// always-refusing throttle at every step.
    public static func handler<Frame: PreviewFrame>(
        interval: Duration?,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) -> Handler<Frame>? {
        guard let interval else { return nil }
        var throttle = PreviewThrottle(interval: interval)
        return { step, total, frame in
            guard throttle.shouldMakeFrame() else { return }
            let started = ContinuousClock.now
            // A frame the packer has no layout for is a dropped glimpse, never a failed run:
            // the pixels nobody sees are the cheapest thing in the loop to go without.
            guard let made = try? frame() else { return }
            let finished = ContinuousClock.now
            throttle.madeFrame(costing: finished - started, at: finished)
            onProgress(
                .frame(
                    after: step, of: total,
                    preview: GenerationPreview(
                        width: made.width, height: made.height, pixels: made.pixels,
                        duration: finished - started)))
        }
    }
}
