import ZephraCore
import ZephraEngine

/// How far the run in flight has got, for the step bar the capsule, its lip and the running
/// card all draw.
///
/// The count is the run's, never the slider's. Once the loop reports, the event's own total is
/// authoritative; before that it is the steps the run in flight was queued with; and only with
/// nothing running is it the next run's, which is what the capsule is set to. The bar stays
/// up, full, from the last step until the result lands, since the run is not over when the
/// steps are. Reading the
/// slider while a run was in flight drew nine segments over a four-step run the moment the
/// slider moved, and a queued nine-step run behind a four-step one drew nine from the start.
nonisolated struct StepProgress: Equatable {
    /// How many steps have finished.
    let completed: Int
    /// How many steps the run has.
    let total: Int
    /// Whether the loop is reporting; the bar is invisible the rest of the time.
    let isRunning: Bool

    init(completed: Int, total: Int, isRunning: Bool) {
        self.completed = completed
        self.total = total
        self.isRunning = isRunning
    }

    /// Works the bar out from the engine's state, the settings of the run in flight, and the
    /// settings the next run would use. On the main actor because `denoisingProgress` is.
    @MainActor
    init(state: EngineState, running: GenerationSettings?, next: GenerationSettings) {
        if let progress = state.denoisingProgress {
            self.init(completed: progress.step, total: progress.total, isRunning: true)
        } else if state.isFinishing {
            // Every step has landed and the latents are being decoded, or the clip encoded. The
            // bar stays up and full: taken down here it said "done" over a decode that runs for
            // tens of seconds on a 121-frame clip, with the last frame sitting still under it.
            let total = running?.steps ?? next.steps
            self.init(completed: total, total: total, isRunning: true)
        } else {
            self.init(completed: 0, total: running?.steps ?? next.steps, isRunning: false)
        }
    }
}
