import Foundation
import ZephraEngine

/// `ZEPHRA_GENERATE_ON_LAUNCH=<prompt>` presses Generate once the model is ready.
///
/// A debugging hook, beside `ZEPHRA_PREVIEW_STATE`: the way to run one real generation in the
/// app itself from a shell, with the app's own window, limits and preview frames, on a Mac
/// nobody is sitting at. The bench measures the model without the window; a failure that needs
/// the window on screen, as a GPU reset under the canvas's compositing did, needs this instead.
/// The variable's value is the prompt; everything else is the saved settings. Debug builds
/// only; in Release this is inert, the same rule `ZEPHRA_PREVIEW_STATE` follows and for the
/// same reason — a shipped, signed Zephra has no business starting a generation, unattended,
/// because a stray environment variable happened to be set.
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

    /// The prompt named in `environment`, or nil when the variable is absent or empty. Pure,
    /// so it is tested; `prompt` is the one place it is asked of the real process environment,
    /// and only in Debug.
    static func resolvedPrompt(from environment: [String: String]) -> String? {
        guard let value = environment[variable], !value.isEmpty else { return nil }
        return value
    }

    /// The reference path named in `environment`, or nil when the variable is absent or empty.
    /// Pure, for the same reason `resolvedPrompt(from:)` is.
    static func resolvedReference(from environment: [String: String]) -> URL? {
        guard let value = environment[referenceVariable], !value.isEmpty else { return nil }
        return URL(filePath: value)
    }

    /// The prompt to generate on launch, or nil when the hook is not set. `#if DEBUG` here,
    /// not around the call site: `prompt` reading nil in Release is what makes `run(on:)`
    /// inert on its own, the way `InterfacePreview.requestedState` does, so nothing outside
    /// this file has to know the hook is Debug-only.
    static var prompt: String? {
        #if DEBUG
        resolvedPrompt(from: ProcessInfo.processInfo.environment)
        #else
        nil
        #endif
    }

    /// The picture to put in the well before generating, or nil when the hook is not set. This
    /// needs no `#if DEBUG` of its own: `run(on:)` reads it only after `prompt`, which is
    /// already nil in Release, so it is never asked.
    static var reference: URL? {
        resolvedReference(from: ProcessInfo.processInfo.environment)
    }

    /// Waits for the bootstrap to leave the model ready, puts the picture in if there is one,
    /// then queues one generation.
    @MainActor
    static func run(on store: GenerationStore) async {
        guard let prompt else { return }
        // Ready, or able to become ready: under on-demand nothing is loaded at launch and the
        // press of Generate below is what reads the weights in, so waiting for `.ready` there
        // would spin for the life of the process. The survey has to have landed first either
        // way — `canLoad` reads `availability`, and an empty map answers yes about every model
        // on the list, so without this the wait falls through on its first tick and Generate is
        // pressed before the disk has been looked at.
        while store.availability.isEmpty
            || (store.state != .ready && !store.canLoad(store.descriptor))
        {
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
