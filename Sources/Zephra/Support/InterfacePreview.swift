import Foundation
import ZephraCore
import ZephraEngine

/// Launches the app frozen in one engine state, with no model and no network, so the
/// interface can be screenshotted and inspected on its own.
///
/// Set `ZEPHRA_PREVIEW_STATE` to `ready`, `image`, `editing`, `generating`, `queued`, `batch`,
/// `library`, `downloading`, `building`, or `failed` before launching. Debug builds only; in
/// Release this is inert.
enum InterfacePreview {
    /// A store frozen in the requested state, or nil for a normal launch. The frozen store has
    /// no backend, so `bootstrap()` on it does nothing and no model is ever looked for.
    static func store() -> GenerationStore? {
        guard let state = requestedState else { return nil }
        switch name {
        case "batch":
            let run = PreviewImages.run(of: 4)
            let store = GenerationStore.preview(state: state, images: run)
            store.settings = run[0].settings
            return store
        case "queued":
            let waiting = queuedRun()
            let store = GenerationStore.preview(
                state: state,
                running: waiting.first,
                queue: Array(waiting.dropFirst())
            )
            // The capsule draws its step segments from `settings`, so a frozen window whose
            // prompt and step count did not match the run would contradict itself.
            store.settings = waiting[0].settings
            return store
        default:
            // The editing preview runs against an invented model that reads a reference, so the
            // well beside the prompt is there to be screenshotted.
            let descriptor = name == "editing" ? PreviewModel.editing : ModelCatalog.default
            return GenerationStore.preview(
                state: state, image: frozenImage(for: state), descriptor: descriptor)
        }
    }

    /// Where the frozen window is looking. Stated rather than restored, so a screenshot build
    /// shows the same thing on every machine.
    static func workspace() -> WorkspaceSelection? {
        guard requestedState != nil else { return nil }
        return WorkspaceSelection(pane: name == "library" ? .library : .canvas)
    }

    /// A library with no folder behind it, or nil for a normal launch. Nothing in it is read
    /// from or written to a disk, so a frozen window shows a full grid on a machine that has
    /// never generated anything.
    static func index() -> LibraryIndex? {
        guard requestedState != nil else { return nil }
        return LibraryIndex.preview(count: 38)
    }

    /// A run of `count` seeds of one prompt, the first of which is the one being rendered.
    /// Shared with the `#Preview`s of the queue, so the frozen window and the previews of its
    /// parts are showing the same thing.
    static func queuedRun(of count: Int = 3) -> [QueuedGeneration] {
        let batch = UUID()
        let settings = GenerationSettings(
            prompt: "a red bicycle against a limestone wall",
            size: ImageSize(width: 1024, height: 1024),
            steps: 4,
            guidance: 0,
            seed: 8_123_447_209_115_662
        )
        return (0..<count).map { index in
            var seeded = settings
            seeded.seed &+= UInt64(index)
            return QueuedGeneration(
                model: ModelCatalog.default,
                settings: seeded,
                batchID: batch,
                batchIndex: index
            )
        }
    }

    private static func frozenImage(for state: EngineState) -> GeneratedImage? {
        switch state {
        case .generating, .cancelling: PreviewImages.sample()
        case .ready where name == "image": PreviewImages.sample()
        case .ready where name == "editing":
            PreviewImages.sample(reference: PreviewImages.referencePNG())
        default: nil
        }
    }

    private static var name: String? {
        ProcessInfo.processInfo.environment["ZEPHRA_PREVIEW_STATE"]
    }

    private static var requestedState: EngineState? {
        #if DEBUG
        switch name {
        case "ready", "image", "editing", "batch", "library":
            return .ready
        case "generating":
            return .generating(GenerationProgressEvent(
                phase: .denoising(step: 4, of: 9),
                fraction: 0.44,
                secondsPerStep: 2.1
            ))
        case "queued":
            return .generating(GenerationProgressEvent(
                phase: .denoising(step: 3, of: 4),
                fraction: 0.75,
                secondsPerStep: 8.2
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
