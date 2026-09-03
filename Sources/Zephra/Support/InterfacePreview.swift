import Foundation
import ZephraCore
import ZephraEngine

/// Launches the app frozen in one engine state, with no model and no network, so the
/// interface can be screenshotted and inspected on its own.
///
/// Set `ZEPHRA_PREVIEW_STATE` to `ready`, `image`, `editing`, `generating`, `downloading`,
/// `building`, or `failed` before launching. Debug builds only; in Release this is inert.
enum InterfacePreview {
    /// A store frozen in the requested state, or nil for a normal launch. The frozen store has
    /// no backend, so `bootstrap()` on it does nothing and no model is ever looked for.
    static func store() -> GenerationStore? {
        guard let state = requestedState else { return nil }
        let image: GeneratedImage? = switch state {
        case .generating, .cancelling: PreviewImages.sample()
        case .ready where name == "image": PreviewImages.sample()
        case .ready where name == "editing":
            PreviewImages.sample(reference: PreviewImages.referencePNG())
        default: nil
        }
        // The editing preview runs against an invented model that reads a reference, so the
        // well beside the prompt is there to be screenshotted.
        let descriptor = name == "editing" ? PreviewModel.editing : ModelCatalog.default
        return GenerationStore.preview(state: state, image: image, descriptor: descriptor)
    }

    private static var name: String? {
        ProcessInfo.processInfo.environment["ZEPHRA_PREVIEW_STATE"]
    }

    private static var requestedState: EngineState? {
        #if DEBUG
        switch name {
        case "ready", "image", "editing":
            return .ready
        case "generating":
            return .generating(GenerationProgressEvent(
                phase: .denoising(step: 4, of: 9),
                fraction: 0.44,
                secondsPerStep: 2.1
            ))
        case "downloading":
            return .downloading(DownloadProgressEvent(
                completedFiles: 3,
                totalFiles: 11,
                fraction: 0.34,
                bytesPerSecond: 46_000_000
            ))
        case "building":
            return .building(BuildProgressEvent(
                component: "transformer",
                completedComponents: 0,
                totalComponents: 2,
                fraction: 0.41
            ))
        case "failed":
            return .failed(.backend(.loadFailed("not enough free memory")))
        default:
            return nil
        }
        #else
        return nil
        #endif
    }
}
