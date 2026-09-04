import ZephraCore

/// Measures the pace of a diffusion loop so the interface can show a countdown even when the
/// backend does not time itself. It keeps a short rolling mean rather than an average over the
/// whole run, because the first step of a generation is always slower than the rest.
///
/// It measures a pace and nothing more: the countdown itself is derived from the pace by
/// `GenerationProgressEvent.estimatedSecondsRemaining`, which is where the interface reads it.
struct StepTimer {
    /// How many recent step intervals the rolling mean covers.
    static let window = 3

    private var previousTick: ContinuousClock.Instant?
    private var intervals: [Double] = []

    /// Creates a timer that has not seen a step yet.
    init() {}

    /// The mean length of the last few steps, absent until one full step has been timed.
    var secondsPerStep: Double? {
        guard !intervals.isEmpty else { return nil }
        return intervals.reduce(0, +) / Double(intervals.count)
    }

    /// Records that a step boundary just went past.
    mutating func tick(at instant: ContinuousClock.Instant = ContinuousClock.now) {
        defer { previousTick = instant }
        guard let previousTick else { return }
        intervals.append((instant - previousTick).seconds)
        if intervals.count > Self.window {
            intervals.removeFirst(intervals.count - Self.window)
        }
    }

    /// The event as the interface should see it: the backend's own pace when it reports one,
    /// ours when it does not. Only denoising steps are timed; the other phases are not periodic.
    mutating func annotated(
        _ event: GenerationProgressEvent,
        at instant: ContinuousClock.Instant = ContinuousClock.now
    ) -> GenerationProgressEvent {
        guard case .denoising = event.phase else { return event }
        tick(at: instant)
        guard event.secondsPerStep == nil, let secondsPerStep else { return event }
        return GenerationProgressEvent(
            phase: event.phase,
            fraction: event.fraction,
            secondsPerStep: secondsPerStep,
            // Rebuilt field by field, so anything the backend attached has to be carried
            // across by name. A frame dropped here would never reach the canvas.
            preview: event.preview
        )
    }
}
