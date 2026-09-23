import Foundation

/// What can go wrong in a backend, phrased so the message can be shown to the user as-is.
public enum BackendError: Error, Sendable, Hashable, LocalizedError {
    /// The requested model has no implementation or no weights on disk.
    case modelNotAvailable(String)
    /// The download did not finish. The string says why, in a sentence a person can act on,
    /// because "check your connection" is the wrong advice for a missing repository or a full disk.
    case downloadFailed(String)
    /// The weights are present but could not be read into memory.
    case loadFailed(String)
    /// Inference started but did not produce an image.
    case generationFailed(String)
    /// The GPU stopped answering part-way through: another process faulted the device, the
    /// driver recovered it, and this process's command buffer came back discarded. The payload
    /// is the runtime's own text, which is logged and never shown: it names a command buffer.
    case deviceFailed(String)
    /// The same lost run, named by the driver as the innocent victim of somebody else's fault
    /// (`kIOGPUCommandBufferCallbackErrorInnocentVictim`): another process — WindowServer, on
    /// every one bender has recorded — faulted the GPU, and this process's buffer was thrown away
    /// in the recovery. Nothing of ours is wrong and the weights are fine, so the engine runs the
    /// job once more by itself (`GenerationStore+FaultRerun`); a second one fails as
    /// `deviceFailed` does, in the same words. The payload is the runtime's own text.
    case deviceVictim(String)
    /// The GPU is gone for the rest of this process: the driver has put this client on its
    /// ignore list and completes its command buffers without running them
    /// (`kIOGPUCommandBufferCallbackErrorSubmissionsIgnored`). Nothing in the app recovers it —
    /// an unload, a reload and a switch to another model were each measured failing in a third
    /// of a second — so this is not a lost run but a lost launch, and the remedy is to relaunch.
    /// The payload is the runtime's own text, logged and never shown.
    case deviceLost(String)
    /// The settings cannot be run by this model.
    case invalidSettings(String)
    /// The work was cancelled before it finished.
    case cancelled

    /// What a person is told when the GPU has gone for this launch. One sentence, in one
    /// place, because the canvas, the engine's own failure and a paired phone's refusal all say
    /// it and two wordings would read as two different faults.
    public static let deviceLostSentence =
        "Zephra has lost the GPU and has to relaunch to get it back."

    /// A short, plain-language explanation, with a next step wherever there is one.
    public var errorDescription: String? {
        switch self {
        case let .modelNotAvailable(name):
            "\(name) isn't on this Mac. Choose another model from the menu."
        case let .downloadFailed(reason):
            "Couldn't download the model. \(reason)"
        case .loadFailed:
            "Couldn't load the model. Free up some memory and try again."
        case .generationFailed:
            "The image couldn't be generated. Try again, or lower the size or step count."
        case .deviceFailed, .deviceVictim:
            "The GPU stopped responding and this run was lost. Try again."
        case .deviceLost:
            Self.deviceLostSentence
        case let .invalidSettings(reason):
            "These settings won't run: \(reason)"
        case .cancelled:
            "Generation was canceled."
        }
    }
}
