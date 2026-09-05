import Foundation
import ZephraEngine

/// `ZEPHRA_GENERATE_ON_LAUNCH=<prompt>` presses Generate once the model is ready.
///
/// A debugging hook, beside `ZEPHRA_PREVIEW_STATE`: the way to run one real generation in the
/// app itself from a shell, with the app's own window, limits and preview frames, on a Mac
/// nobody is sitting at. The bench measures the model without the window; a failure that needs
/// the window on screen, as a GPU reset under the canvas's compositing did, needs this instead.
/// The variable's value is the prompt; everything else is the saved settings.
enum LaunchGeneration {
    static let variable = "ZEPHRA_GENERATE_ON_LAUNCH"

    /// The prompt to generate on launch, or nil when the hook is not set.
    static var prompt: String? {
        guard let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Waits for the bootstrap to leave the model ready, then queues one generation.
    @MainActor
    static func run(on store: GenerationStore) async {
        guard let prompt else { return }
        while store.state != .ready {
            if case .failed = store.state { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
        store.settings.prompt = prompt
        store.generateFromInterface(count: 1)
    }
}
