import Foundation
import ZephraCore
import ZephraEngine

/// Where the engine meets the interface: every stored preference it acts on is applied here,
/// on the way in, because `ZephraEngine` knows nothing about `UserDefaults`, and the one or two
/// questions the interface asks in its own terms are answered here too.
extension GenerationStore {
    /// Whether the canvas has something to describe, which is what decides whether there is an
    /// inspector to show beside it: a picture, or a run it is following, which has a prompt and
    /// a size to show from the moment it starts.
    var hasPicture: Bool { current != nil || isShowingRun }

    /// The step bar's reading: the run in flight's steps, not the slider's. One place, so the
    /// capsule, its lip and the running card cannot count differently.
    var stepProgress: StepProgress {
        StepProgress(state: state, running: running?.settings, next: settings, chain: running?.chain)
    }

    /// Whether the run in flight makes a clip, which is what its phases are worded for.
    var runMakesClip: Bool { (running?.settings.frames ?? 1) > 1 }

    /// What the run is doing once its last step has landed, in words, or nil while the loop is
    /// still running. The canvas puts it over the last frame with a spinner, because the frames
    /// have stopped coming and nothing else on the canvas moves for what can be tens of seconds.
    var finishingPhase: String? {
        guard state.isFinishing else { return nil }
        return state.generationPhase(clip: runMakesClip)
    }

    /// Points the store at the models folder, then loads the model where the loading mode says
    /// to. The root view's only entry point. The preferences a load honours — warm-up, the
    /// loading mode, the idle clock — are set on the store by the composition root and followed
    /// there, so no door re-reads them.
    ///
    /// `loadingModel: false` reads what is on disk and stops there, for a launch that opens on
    /// the first-launch chooser: the cards need `availability` to say what each model costs,
    /// and a launch nobody has chosen a model on must not start a transfer.
    func bootstrapFromInterface(loadingModel: Bool = true) async {
        await setModelLocations(AppSettings.modelLocations())
        if loadingModel { await bootstrap() } else { await surveyAvailability() }
    }

    /// Loads the model picked in the first-launch chooser.
    ///
    /// A first-launch pick is an explicit "load it now", whichever loading mode is in force, so
    /// it is a choice and then a load rather than only a choice. `switchModel` refuses a pick of
    /// the model already chosen (`GenerationStore+Switching`), which on a first launch is
    /// whatever `ModelCatalog.default(fitting:)` answered, so that case skips straight to the
    /// load; under `.automatic` the switch has already loaded and `loadModel()` is a no-op.
    func chooseFirstModel(_ model: ModelDescriptor) {
        if model.id != descriptor.id { switchModel(to: model) }
        loadModel()
    }

    /// Restarts a load that failed or was cancelled.
    func retryFromInterface() {
        retry()
    }

    /// Chooses a different model. Whether the weights follow is `loadingMode`'s answer, made
    /// once in the engine rather than by each door. The one way the interface changes model.
    func switchModelFromInterface(to descriptor: ModelDescriptor) {
        switchModel(to: descriptor)
    }

    /// Generates as many seeds as the batch control is set to. The menu bar's Generate and the
    /// return key come through here, so every route does the same thing as the button.
    func generateFromInterface() {
        generateFromInterface(count: AppSettings.integer(AppSettings.batchCount))
    }

    /// Picks a fresh seed if the preference asks for one, then queues `count` seeds of it.
    ///
    /// The randomize-seed preference is applied once, before the batch is expanded, so the
    /// first image of a batch is exactly what a batch of one would have produced.
    func generateFromInterface(count: Int) {
        guard canQueue else { return }
        if AppSettings.flag(AppSettings.randomizeSeedEachRun) { randomizeSeed() }
        generate(count: count)
    }
}
