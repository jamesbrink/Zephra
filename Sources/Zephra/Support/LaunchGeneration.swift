import Foundation
import ZephraEngine

/// `ZEPHRA_GENERATE_ON_LAUNCH=<prompt>` presses Generate once the model is ready.
///
/// A debugging hook, beside `ZEPHRA_PREVIEW_STATE`: the way to run one real generation in the
/// app itself from a shell, with the app's own window, limits and preview frames, on a Mac
/// nobody is sitting at. The bench measures the model without the window; a failure that needs
/// the window on screen, as a GPU reset under the canvas's compositing did, needs this instead.
/// The variable's value is the prompt; everything else is the saved settings.
///
/// `ZEPHRA_REFERENCE_ON_LAUNCH=<path to a picture>` puts that picture in the well first,
/// through the same door a drop takes (`GenerationStore.adoptReference`, so the read happens
/// off the main actor and the 1024-pixel cap applies), and Generate waits for it to land the
/// way it waits for any picture on its way in. With a video model chosen that is an
/// image-to-video run from a shell. Read alone it does nothing: a picture with no prompt is
/// not a request.
enum LaunchGeneration {
    static let variable = "ZEPHRA_GENERATE_ON_LAUNCH"
    static let referenceVariable = "ZEPHRA_REFERENCE_ON_LAUNCH"

    /// The prompt to generate on launch, or nil when the hook is not set.
    static var prompt: String? {
        guard let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty else {
            return nil
        }
        return value
    }

    /// The picture to put in the well before generating, or nil when the hook is not set.
    static var reference: URL? {
        guard let value = ProcessInfo.processInfo.environment[referenceVariable], !value.isEmpty
        else { return nil }
        return URL(filePath: value)
    }

    /// Waits for the bootstrap to leave the model ready, puts the picture in if there is one,
    /// then queues one generation.
    @MainActor
    static func run(on store: GenerationStore) async {
        guard let prompt else { return }
        while store.state != .ready {
            if case .failed = store.state { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if let reference {
            store.adoptReference(origin: nil) { ReferenceImageEncoder.pngData(contentsOf: reference) }
            while store.isAdoptingReference {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        store.settings.prompt = prompt
        store.generateFromInterface(count: 1)
    }
}
