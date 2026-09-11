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

    /// Applies the launch preferences, then loads the model. The root view's only entry point.
    ///
    /// `loadingModel: false` reads what is on disk and stops there, for a launch that opens on
    /// the first-launch chooser: the cards need `availability` to say what each model costs,
    /// and a launch nobody has chosen a model on must not start a transfer.
    func bootstrapFromInterface(loadingModel: Bool = true) async {
        warmsUpAfterLoad = AppSettings.flag(AppSettings.warmUpOnLaunch)
        await setModelLocations(AppSettings.modelLocations())
        if loadingModel { await bootstrap() } else { await surveyAvailability() }
    }

    /// Loads the model picked in the first-launch chooser.
    ///
    /// `switchModel` refuses a pick of the model already chosen (`GenerationStore+Switching`),
    /// which on a first launch is whatever `ModelCatalog.default(fitting:)` answered — so
    /// pressing the recommended card would otherwise do nothing at all. That case starts the
    /// load directly, which from `.idle` with nothing resident is the same work.
    func chooseFirstModel(_ model: ModelDescriptor) {
        warmsUpAfterLoad = AppSettings.flag(AppSettings.warmUpOnLaunch)
        if model.id == descriptor.id {
            retry()
        } else {
            switchModel(to: model)
        }
    }

    /// Restarts a load that failed or was cancelled, honouring the same preferences.
    func retryFromInterface() {
        warmsUpAfterLoad = AppSettings.flag(AppSettings.warmUpOnLaunch)
        retry()
    }

    /// Loads a different model, honouring the same launch preferences the first load used.
    /// The one way the interface changes model.
    func switchModelFromInterface(to descriptor: ModelDescriptor) {
        warmsUpAfterLoad = AppSettings.flag(AppSettings.warmUpOnLaunch)
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
