import Foundation

/// How often a running generation may stop to decode a preview frame.
///
/// A frame is a whole pass through an autoencoder, small but not free, taken out of the time the
/// image itself is being made. It exists to show that something is happening, and something is
/// happening at a pace a person reads in seconds, so this is deliberately far slower than the
/// step rate of every model in the catalog.
///
/// It lives here, in the Foundation-only layer, rather than in the kits: a kit is one family's
/// arithmetic and knows nothing about how often a host wants to look. The backends own a
/// throttle each and decide, per step, whether to spend the decode at all — which is why the
/// pipelines hand out a *way to make* a frame rather than a frame. The interval itself comes
/// down from the composition root in `InferenceEnvironment.previewInterval`, where
/// `ZEPHRA_PREVIEW_INTERVAL_MS` is read once; nil there is frames off.
public struct PreviewThrottle: Sendable {
    /// The interval every family starts from. Measured: the pooled decode is well under a fifth
    /// of this for each of them, so the frames cost a few percent of a run.
    public static let defaultInterval: Duration = .milliseconds(750)

    /// The shortest gap between two frames.
    public let interval: Duration

    private var lastFrame: ContinuousClock.Instant?

    /// Creates a throttle that has not let a frame through yet, so the first ask succeeds.
    public init(interval: Duration = Self.defaultInterval) {
        self.interval = interval
    }

    /// Whether a frame may be made now, recording that it was when the answer is yes.
    ///
    /// The first ask is always yes: a run should show something as soon as it has anything to
    /// show, rather than staying blank for the first interval.
    public mutating func shouldMakeFrame(
        at instant: ContinuousClock.Instant = .now
    ) -> Bool {
        if let lastFrame, instant - lastFrame < interval { return false }
        lastFrame = instant
        return true
    }
}
