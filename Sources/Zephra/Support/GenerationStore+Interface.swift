import Foundation
import ZephraCore
import ZephraEngine

/// Where the engine meets the app's preferences. `ZephraEngine` knows nothing about
/// `UserDefaults`, so every stored preference it acts on is applied here, on the way in.
extension GenerationStore {
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
