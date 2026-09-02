import Foundation
import ZephraEngine

/// The one way the interface starts a generation, so the "new seed each run" preference is
/// honoured everywhere: the button, the return key, and the menu bar.
extension GenerationStore {
    /// Picks a fresh seed if the preference asks for one, then generates.
    func generateFromInterface() {
        guard canQueue else { return }
        let randomize = UserDefaults.standard.object(forKey: AppSettings.randomizeSeedEachRun) as? Bool
            ?? AppSettings.initialRandomizeSeedEachRun
        if randomize { randomizeSeed() }
        generate()
    }
}
