import ZephraLinkProtocol

/// How far the run in flight has got, for the segments that ride the capsule's top edge.
///
/// The Mac's `StepProgress` works this out from an engine state, the run in flight's settings
/// and the next run's; here there is only what the Mac already decided and sent, which is the
/// point of `EngineStateDTO` carrying `isFinishing` rather than leaving it to be derived twice.
/// The bar stays up and full from the last step until the result lands, because the run is not
/// over when the steps are.
struct StepProgress: Equatable {
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

    /// The bar the Mac's engine state asks for.
    init(_ engine: EngineStateDTO?) {
        guard let engine, let steps = engine.steps, steps > 0 else {
            self.init(completed: 0, total: 0, isRunning: false)
            return
        }
        if engine.isFinishing {
            self.init(completed: steps, total: steps, isRunning: true)
        } else if engine.kind == .generating, let step = engine.step {
            self.init(completed: min(max(step, 0), steps), total: steps, isRunning: true)
        } else {
            self.init(completed: 0, total: steps, isRunning: false)
        }
    }
}
