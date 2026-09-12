import Foundation

/// Where the Mac's engine is, flattened for the phone.
///
/// A struct of scalars rather than `EngineState`'s enum on the wire. Two reasons. The engine's
/// cases carry progress events that carry a decoded preview frame, and a quarter of a megabyte
/// of pixels must never ride inside a state update — previews have a message kind of their own.
/// And the facts the Mac derives from a case (is this busy, is the run finishing) are stored
/// here rather than recomputed there, so the phone never has to know a rule the Mac already
/// knows and the two can never disagree about one.
public struct EngineStateDTO: Codable, Hashable, Sendable {
    /// Which of `EngineState`'s cases this is.
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case idle, checkingModel, downloading, building, loading, warmingUp, ready
        case generating, upscaling, cancelling, failed
    }

    /// The case.
    public var kind: Kind
    /// What is happening, in the engine's own words: "Denoising", "Decoding", "Saving".
    public var phase: String?
    /// The step the diffusion loop is on, counting from one, while one is running.
    public var step: Int?
    /// How many steps that loop has.
    public var steps: Int?
    /// Completion from 0 to 1 for whatever is running, or nil where nothing measures one.
    public var fraction: Double?
    /// Measured pace of the diffusion loop, absent until a step has finished.
    public var secondsPerStep: Double?
    /// Bytes transferred and to transfer, while downloading.
    public var completedBytes: Int64?
    /// How many bytes the download covers.
    public var totalBytes: Int64?
    /// Files finished and files in all, while downloading.
    public var completedFiles: Int?
    /// How many files the download covers.
    public var totalFiles: Int?
    /// Current transfer rate, where one has been measured.
    public var bytesPerSecond: Double?
    /// The component being packed, while building.
    public var component: String?
    /// Components written and components in all, while building.
    public var completedComponents: Int?
    /// How many components the build covers.
    public var totalComponents: Int?
    /// Tiles finished and tiles in all, while upscaling.
    public var completedTiles: Int?
    /// How many tiles the picture was cut into.
    public var totalTiles: Int?
    /// The model this state is about, where the state is about one.
    public var modelID: String?
    /// What went wrong, on a failure, in the words the Mac would show.
    public var message: String?
    /// Whether the engine is busy with work that shows progress.
    public var isBusy: Bool
    /// Whether every step has landed and the run is being finished: latents decoded, a clip's
    /// frames encoded. Derived on the Mac, because it is the Mac's rule.
    public var isFinishing: Bool
    /// Whether a new generation may start right now.
    public var acceptsGeneration: Bool
    /// Whether a generation may be *queued* right now: started at once, or put behind the one
    /// the Mac is already rendering. Wider than `acceptsGeneration`, which is the engine
    /// standing idle, and it is the fact a phone's Generate button reads — the Mac's own
    /// `canQueue` says the same thing about the Mac's button. Stamped by the host rather than
    /// derived from `EngineState` alone, since whether the store is working down its queue is
    /// the store's fact and not the state's.
    public var canQueue: Bool

    /// Creates a state update. Everything but the case and the four derived facts defaults to
    /// absent, since each case fills in only its own fields.
    public init(
        kind: Kind,
        phase: String? = nil,
        step: Int? = nil,
        steps: Int? = nil,
        fraction: Double? = nil,
        secondsPerStep: Double? = nil,
        completedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        completedFiles: Int? = nil,
        totalFiles: Int? = nil,
        bytesPerSecond: Double? = nil,
        component: String? = nil,
        completedComponents: Int? = nil,
        totalComponents: Int? = nil,
        completedTiles: Int? = nil,
        totalTiles: Int? = nil,
        modelID: String? = nil,
        message: String? = nil,
        isBusy: Bool = false,
        isFinishing: Bool = false,
        acceptsGeneration: Bool = false,
        canQueue: Bool = false
    ) {
        self.kind = kind
        self.phase = phase
        self.step = step
        self.steps = steps
        self.fraction = fraction
        self.secondsPerStep = secondsPerStep
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.bytesPerSecond = bytesPerSecond
        self.component = component
        self.completedComponents = completedComponents
        self.totalComponents = totalComponents
        self.completedTiles = completedTiles
        self.totalTiles = totalTiles
        self.modelID = modelID
        self.message = message
        self.isBusy = isBusy
        self.isFinishing = isFinishing
        self.acceptsGeneration = acceptsGeneration
        self.canQueue = canQueue
    }
}
