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

    /// Applies the launch preferences, then loads the model. The root view's only entry point.
    func bootstrapFromInterface() async {
        warmsUpAfterLoad = AppSettings.flag(AppSettings.warmUpOnLaunch)
        await bootstrap()
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
