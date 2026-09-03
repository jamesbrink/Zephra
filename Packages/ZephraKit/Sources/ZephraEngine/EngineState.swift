import ZephraCore

/// Where the engine is in its life cycle. The UI renders exactly one of these at a time.
public enum EngineState: Hashable, Sendable {
    /// Nothing has happened yet.
    case idle
    /// Looking for the model on disk.
    case checkingModel
    /// Fetching weights from the network.
    case downloading(DownloadProgressEvent)
    /// Packing a downloaded release into the variant this Mac loads. Its own state rather than
    /// a phase of downloading because the wording has to be true at the one moment a first-time
    /// user is most likely to think the app has hung: a minute of disk and Metal work at several
    /// gigabytes resident, with nothing moving over the network.
    case building(BuildProgressEvent)
    /// Reading weights into memory.
    case loading(GenerationPhase)
    /// Running a throwaway generation so the first real one is not slow.
    case warmingUp
    /// Loaded and waiting for a prompt.
    case ready
    /// Producing an image.
    case generating(GenerationProgressEvent)
    /// A cancel was requested; finishing the current step.
    case cancelling
    /// Stopped on an error the user needs to see.
    case failed(EngineError)

    /// Whether a new generation may start right now.
    public var acceptsGeneration: Bool { self == .ready }

    /// Whether the engine is busy with work that shows progress.
    public var isBusy: Bool {
        switch self {
        case .idle, .ready, .failed: return false
        default: return true
        }
    }
}
