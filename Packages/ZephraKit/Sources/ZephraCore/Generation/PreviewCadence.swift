/// How often a running generation stops to show what it has so far.
///
/// A per-run value rather than a backend setting: the store decides it for each run and
/// `InferenceActor` puts it in `current` around the backend's `generate`, so no backend, no
/// factory and no `ImageGenerationBackend` signature learns it. Every family already builds its
/// preview hook with `PreviewFrameReporter.handler` at the top of `generate`, inside that very
/// task, and that is where it is read.
public enum PreviewCadence: String, Sendable, Hashable, CaseIterable {
    /// No frames at all: the run is a placeholder until the picture lands.
    case off
    /// A frame every so often, held back by `PreviewThrottle`'s two clocks so frames never
    /// cost more than about a tenth of a run. What every run did before there was a choice.
    case balanced
    /// A frame after every step but the last, whatever it costs. On Qwen-Image 2.1, whose
    /// frame is the picture's own decode, that is about a second a step.
    case everyStep

    /// The cadence of the run the current task is making. Balanced unless somebody said
    /// otherwise, so a backend called from a test, the bench or a tool behaves as it always did.
    @TaskLocal public static var current: PreviewCadence = .balanced

    /// What a picker calls it.
    public var title: String {
        switch self {
        case .off: "Off"
        case .balanced: "Balanced"
        case .everyStep: "Every step"
        }
    }
}
