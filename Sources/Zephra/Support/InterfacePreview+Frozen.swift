import Foundation
import ZephraCore
import ZephraEngine

/// Which state `ZEPHRA_PREVIEW_STATE` asked for, and the made-up run or picture that state
/// needs behind it to be worth photographing.
///
/// The other half of `InterfacePreview` — that file is the four things the composition root
/// calls, this one is how each state is stood up. Split because between them they were past
/// the file-size rule, and this is the seam: nothing here is called from outside the type.
extension InterfacePreview {
    /// A store with a run in flight, a frame from it, and `seeds - 1` more waiting behind it.
    ///
    /// `watching` is the state that cannot be reached any other way: the model working while
    /// the canvas shows an earlier picture, which is what `followsRun` being false means. The
    /// other two are following, so the canvas is the run's own frames and `current` is nothing.
    static func runningStore(state: EngineState, seeds: Int) -> GenerationStore {
        let watching = name == "watching"
        let flight = queuedRun(of: seeds, steps: stepCount(of: state))
        let store = GenerationStore.preview(
            state: state,
            image: watching ? PreviewImages.sample() : nil,
            running: flight.first,
            queue: Array(flight.dropFirst()),
            // `starting` is the run before its first frame, which is what the placeholder in
            // the run's rectangle is for; every other running build has a frame in hand.
            livePreview: name == "starting" ? nil : PreviewImages.frame(),
            following: watching ? false : nil
        )
        // The capsule draws its step segments from `settings`, so a frozen window whose
        // prompt and step count did not match the run would contradict itself.
        store.settings = flight[0].settings
        return store
    }

    /// The picture on the canvas for the states that have one. A running generation is not one
    /// of them: it goes through `runningStore`, and what its canvas shows is the run.
    static func frozenImage(for state: EngineState) -> GeneratedImage? {
        switch state {
        case .ready where name == "image": PreviewImages.sample()
        case .ready where name == "tucked": PreviewImages.sample()
        case .ready where isEditingBuild:
            PreviewImages.sample(reference: PreviewImages.referencePNG())
        // Over a picture, because that is where these two have to stay legible: a model
        // chosen from the menu downloads, or fails to, with the last image still up.
        case .downloading, .failed: PreviewImages.sample()
        default: nil
        }
    }

    /// The name the environment asked for, or nil for an ordinary launch. Not private only so
    /// both halves of the type can read it.
    static var name: String? {
        ProcessInfo.processInfo.environment["ZEPHRA_PREVIEW_STATE"]
    }

    /// The engine state that name stands for, or nil when it names nothing. Release builds
    /// answer nil whatever the environment says, which is what makes this inert when shipped.
    static var requestedState: EngineState? {
        #if DEBUG
        switch name {
        case "settings", "ready", "image", "editing", "tucked", "batch", "library", "viewer", "picker":
            return .ready
        case "generating":
            return .generating(GenerationProgressEvent(
                phase: .denoising(step: 4, of: 9),
                fraction: 0.44,
                secondsPerStep: 2.1
            ))
        case "starting":
            return .generating(GenerationProgressEvent(
                phase: .denoising(step: 1, of: 4),
                fraction: 0.1,
                secondsPerStep: 29.7
            ))
        case "queued", "watching":
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
            return .failed(.backend(.downloadFailed(
                DownloadRetry.givingUpMessage("The network connection was lost"))))
        default:
            return nil
        }
        #else
        return nil
        #endif
    }

    /// How many steps the frozen event says the run has, so the run standing up behind it
    /// agrees with the progress on screen. Four for a state with no loop in it.
    private static func stepCount(of state: EngineState) -> Int {
        guard case .generating(let event) = state,
              case .denoising(_, let total) = event.phase
        else { return 4 }
        return total
    }
}
