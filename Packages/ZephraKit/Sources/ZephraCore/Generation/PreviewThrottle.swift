import Foundation

/// How often a running generation may stop to decode a preview frame.
///
/// A frame is a whole pass through an autoencoder, small but not free, taken out of the time the
/// image itself is being made. It exists to show that something is happening, and something is
/// happening at a pace a person reads in seconds, so this is deliberately far slower than the
/// step rate of every model in the catalog.
///
/// Two clocks, and a frame waits on both. The **interval** is the shortest gap between two
/// frames, however cheap they are. The **cost share** is the other way round: a frame that took
/// `t` to make holds the next one until `costShare * t` has passed, so frames never take more
/// than about a tenth of a run's wall time however dear they are. For a frame of a few
/// hundredths of a second the interval is the only clock that ever holds; Qwen-Image 2.1's is
/// the picture's own decode, about a second and a half at 1024 against a step of six, and the
/// share is what keeps that at a frame every third step rather than a fifth of the run.
///
/// It lives here, in the Foundation-only layer, rather than in the kits: a kit is one family's
/// arithmetic and knows nothing about how often a host wants to look. The backends own a
/// throttle each and decide, per step, whether to spend the decode at all — which is why the
/// pipelines hand out a *way to make* a frame rather than a frame. The interval itself comes
/// down from the composition root in `InferenceEnvironment.previewInterval`, where
/// `ZEPHRA_PREVIEW_INTERVAL_MS` is read once; nil there is frames off.
public struct PreviewThrottle: Sendable {
    /// The interval every family starts from. For every family but Qwen-Image 2.1 the pooled
    /// decode is well under a fifth of this, so the frames cost a few percent of a run.
    public static let defaultInterval: Duration = .milliseconds(750)

    /// How many times a frame's own cost must pass before the next frame: one frame in ten
    /// seconds of run for a frame that took one.
    public static let costShare = 10

    /// The shortest gap between two frames.
    public let interval: Duration
    /// Whether a frame's own cost holds the next one back. False only for `everyStep`.
    private let holdsForCost: Bool

    private var lastFrame: ContinuousClock.Instant?
    private var earliestNext: ContinuousClock.Instant?

    /// Creates a throttle that has not let a frame through yet, so the first ask succeeds.
    public init(interval: Duration = Self.defaultInterval) {
        self.init(interval: interval, holdsForCost: true)
    }

    private init(interval: Duration, holdsForCost: Bool) {
        self.interval = interval
        self.holdsForCost = holdsForCost
    }

    /// A throttle that says yes to every ask: no interval and no cost share. What
    /// `PreviewCadence.everyStep` asks for, knowing a frame after every step slows the run by
    /// that frame's cost each step.
    public static var everyStep: PreviewThrottle {
        PreviewThrottle(interval: .zero, holdsForCost: false)
    }

    /// Whether a frame may be made now, recording that it was when the answer is yes.
    ///
    /// The first ask is always yes: a run should show something as soon as it has anything to
    /// show, rather than staying blank for the first interval.
    public mutating func shouldMakeFrame(
        at instant: ContinuousClock.Instant = .now
    ) -> Bool {
        if let lastFrame, instant - lastFrame < interval { return false }
        if let earliestNext, instant < earliestNext { return false }
        lastFrame = instant
        return true
    }

    /// Records what the frame just made cost, holding the next until `costShare` times that
    /// has passed from `instant`, the moment the frame was finished.
    public mutating func madeFrame(
        costing duration: Duration, at instant: ContinuousClock.Instant = .now
    ) {
        guard holdsForCost else { return }
        earliestNext = instant + duration * Self.costShare
    }
}
