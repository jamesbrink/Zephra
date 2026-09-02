import Foundation
import ZephraCore
import ZephraEngine

/// Launches the app frozen in one engine state, with no model and no network, so the
/// interface can be screenshotted and inspected on its own.
///
/// Set `ZEPHRA_PREVIEW_STATE` to `ready`, `image`, `generating`, `downloading`, or `failed`
/// before launching. Debug builds only; in Release this is inert.
enum InterfacePreview {
    /// Whether the app was launched in interface-only mode, which skips `bootstrap()`.
    static var isActive: Bool { requestedState != nil }

    /// A store frozen in the requested state, or nil for a normal launch.
    static func store() -> GenerationStore? {
        guard let state = requestedState else { return nil }
        let image: GeneratedImage? = switch state {
        case .generating, .cancelling: PreviewImages.sample()
        case .ready: name == "image" ? PreviewImages.sample() : nil
        default: nil
        }
        return GenerationStore.preview(state: state, image: image)
    }

    private static var name: String? {
        ProcessInfo.processInfo.environment["ZEPHRA_PREVIEW_STATE"]
    }

    private static var requestedState: EngineState? {
        #if DEBUG
        switch name {
        case "ready", "image":
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
