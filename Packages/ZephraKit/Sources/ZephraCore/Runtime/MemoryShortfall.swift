/// A load or a run this Mac has not got the memory for, and the one sentence it is said in.
///
/// An error rather than a verdict, because the only thing to do with it is refuse: MLX throws
/// its Metal failures from a completion queue no Swift `catch` can reach, so the only safe
/// place to stop is before the allocation is asked for.
public struct MemoryShortfall: Error, Hashable, Sendable {
    /// Which side of a generation was refused.
    public enum Phase: Hashable, Sendable {
        /// Getting the weights in: what `prepare` was about to do.
        case load
        /// The run itself: what a decode at this size and length would take on top of them.
        case run
    }

    /// What the person can do about it. Two answers, because there are two ways to be short:
    /// something else is holding the memory, or the model is being held whole when it need
    /// not be.
    public enum Remedy: Hashable, Sendable {
        /// The memory exists; something else has it.
        case quitOtherApps
        /// The model is held resident by choice and would fit read from disk instead.
        case streamFromDisk

        /// The sentence this remedy is said in.
        public var sentence: String {
            switch self {
            case .quitOtherApps: "Quit other apps and retry."
            case .streamFromDisk:
                "Set Stream weights from disk to Automatic in Settings > Performance."
            }
        }
    }

    /// The model, as a person sees it named.
    public let modelName: String
    /// What this phase would take.
    public let neededBytes: Int64
    /// What there is for it.
    public let freeBytes: Int64
    /// Load or run.
    public let phase: Phase
    /// What to do about it.
    public let remedy: Remedy

    public init(
        modelName: String, neededBytes: Int64, freeBytes: Int64, phase: Phase, remedy: Remedy
    ) {
        self.modelName = modelName
        self.neededBytes = neededBytes
        self.freeBytes = freeBytes
        self.phase = phase
        self.remedy = remedy
    }

    /// What the canvas, the log and a paired phone all say: the two figures and the remedy.
    public var sentence: String {
        "\(modelName) needs \(ByteCount.gigabytes(neededBytes)) and "
            + "\(ByteCount.gigabytes(freeBytes)) is free. \(remedy.sentence)"
    }
}
