import Foundation
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

    /// Picks a fresh seed if the preference asks for one, then generates. The one way the
    /// interface starts a generation: the button, the return key, and the menu bar.
    func generateFromInterface() {
        guard canQueue else { return }
        if AppSettings.flag(AppSettings.randomizeSeedEachRun) { randomizeSeed() }
        generate()
    }
}
